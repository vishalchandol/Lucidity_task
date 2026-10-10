import configparser
import hashlib
from itertools import product
import json
from pathlib import Path
import unittest

from jinja2 import StrictUndefined
from jinja2.nativetypes import NativeEnvironment
import yaml


ROOT = Path(__file__).resolve().parents[1]


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        self.settings = yaml.safe_load((ROOT / "ansible/settings.yml").read_text())
        self.plays = yaml.safe_load((ROOT / "ansible/monitoring.yml").read_text())
        self.environment = NativeEnvironment(undefined=StrictUndefined)
        self.environment.filters.update({
            "to_json": json.dumps,
            "to_nice_json": lambda value: json.dumps(value, indent=4, sort_keys=True),
            "items2dict": lambda value, key_name="key", value_name="value": {
                item[key_name]: item[value_name] for item in value
            },
            "dict2items": lambda value: [{"key": key, "value": item} for key, item in value.items()],
            "hash": lambda value, algorithm: hashlib.new(algorithm, value.encode()).hexdigest(),
            "product": product,
        })

    def render(self, value, **context):
        if isinstance(value, dict):
            return {key: self.render(item, **context) for key, item in value.items()}
        if isinstance(value, list):
            return [self.render(item, **context) for item in value]
        if isinstance(value, str):
            return self.environment.from_string(value).render(**(self.settings | context))
        return value

    def play(self, name):
        return next(play for play in self.plays if play["name"] == name)

    def task(self, tasks, name):
        return next(task for task in tasks if task["name"] == name)

    def alarm_tasks(self):
        return self.play("Manage workload-local disk and heartbeat alarms from the controller")["tasks"][0]["block"]

    def report_tasks(self):
        return self.play("Assemble Linux coverage input and run the local reporter")["tasks"][0]["block"]

    def test_all_yaml_parses(self):
        for path in (ROOT / "ansible").rglob("*.yml"):
            with self.subTest(path=path):
                self.assertIsNotNone(yaml.safe_load(path.read_text()))

    def test_ansible_has_exactly_eight_source_files(self):
        expected = {"README.md", "ansible.cfg", "inventory.aws_ec2.yml", "settings.yml",
                    "requirements.yml", "requirements-controller.txt", "monitoring.yml",
                    "scripts/disk_report.py"}
        actual = {path.relative_to(ROOT / "ansible").as_posix()
                  for path in (ROOT / "ansible").rglob("*")
                  if path.is_file() and "__pycache__" not in path.parts}
        self.assertEqual(actual, expected)
        self.assertLessEqual(len((ROOT / "ansible/monitoring.yml").read_text().splitlines()), 350)
        readme_lines = len((ROOT / "ansible/README.md").read_text().splitlines())
        self.assertGreaterEqual(readme_lines, 60)
        self.assertLessEqual(readme_lines, 90)

    def test_four_plays_load_settings_without_implicit_setup(self):
        self.assertEqual(len(self.plays), 4)
        for play in self.plays:
            self.assertEqual(play["vars_files"], ["settings.yml"])
            self.assertFalse(play["gather_facts"])
            self.assertNotIn("roles", play)
        text = (ROOT / "ansible/monitoring.yml").read_text()
        for removed in ["include_tasks", "import_playbook", "ansible.builtin.template"]:
            self.assertNotIn(removed, text)

    def test_action_is_required_and_operations_are_opt_in(self):
        preflight = self.play("Validate explicit single-account Linux scope")
        gate = preflight["tasks"][0]["ansible.builtin.assert"]["that"][0]
        self.assertNotIn("monitoring_action", self.settings)
        self.assertFalse(self.render("{{ " + gate + " }}"))
        for action in ["configure", "alarms", "audit", "all", "choose-action", ""]:
            self.assertEqual(self.render("{{ " + gate + " }}", monitoring_action=action),
                             action in ["configure", "alarms", "audit"])
        linux = self.play("Configure the agent or collect Linux mount facts")
        alarms = self.play("Manage workload-local disk and heartbeat alarms from the controller")
        reports = self.play("Assemble Linux coverage input and run the local reporter")
        for block, action in [(linux["tasks"][0], "configure"), (linux["tasks"][1], "audit"),
                              (alarms["tasks"][0], "alarms"), (reports["tasks"][0], "audit")]:
            conditions = block["when"] if isinstance(block["when"], list) else [block["when"]]
            gate = "{{ " + conditions[0] + " }}"
            self.assertFalse(self.render(gate))
            for selected in ["configure", "alarms", "audit"]:
                self.assertEqual(self.render(gate, monitoring_action=selected), selected == action)

    def test_connection_settings_select_local_or_ssm(self):
        for host, connection, interpreter in [
            ("localhost", "local", "/controller/python"),
            ("i-0123456789abcdef0", "amazon.aws.aws_ssm", "/usr/bin/python3"),
        ]:
            context = {"inventory_hostname": host, "ansible_playbook_python": "/controller/python"}
            self.assertEqual(self.render(self.settings["ansible_connection"], **context), connection)
            self.assertEqual(self.render(self.settings["ansible_python_interpreter"], **context), interpreter)

    def test_agent_dictionary_json_contract(self):
        config = json.loads(json.dumps(self.render(self.settings["diskmon_agent_configuration"])))
        self.assertTrue(config["agent"]["omit_hostname"])
        metrics = config["metrics"]
        self.assertEqual(metrics["append_dimensions"], {"InstanceId": "${aws:InstanceId}"})
        self.assertEqual(metrics["namespace"], "Enterprise/DiskMonitoring")
        self.assertEqual(set(metrics["metrics_collected"]), {"disk", "mem"})
        disk = metrics["metrics_collected"]["disk"]
        self.assertTrue(disk["drop_device"])
        self.assertEqual(disk["measurement"], ["used_percent", "free", "total"])
        self.assertEqual(disk["metrics_collection_interval"], 60)
        self.assertEqual(disk["resources"], ["*"])
        self.assertEqual(disk["ignore_file_system_types"], self.settings["diskmon_excluded_fstypes"])
        self.assertIn("tmpfs", disk["ignore_file_system_types"])
        self.assertEqual(metrics["metrics_collected"]["mem"]["measurement"], ["used_percent"])

    def test_inventory_is_complete_and_matches_transport(self):
        inventory = yaml.safe_load((ROOT / "ansible/inventory.aws_ec2.yml").read_text())
        self.assertEqual(inventory["filters"], {"instance-state-name": "running"})
        self.assertTrue(inventory["strict_permissions"])
        self.assertTrue(inventory["strict"])
        self.assertFalse(inventory["cache"])
        self.assertEqual(inventory["profile"], self.settings["ansible_aws_ssm_profile"])
        self.assertEqual(inventory["regions"], [self.settings["ansible_aws_ssm_region"]])
        self.assertEqual(inventory["hostnames"], ["instance-id"])
        self.assertEqual(inventory["compose"]["ansible_host"], "instance_id")
        self.assertEqual(inventory["compose"]["ansible_aws_ssm_region"], "placement.region")
        for platform, expected in [("", True), ("windows", False)]:
            self.assertEqual(self.render("{{ " + inventory["groups"]["linux"] + " }}",
                                         platform=platform), expected)

    def test_preflight_checks_inputs_and_role_before_operations(self):
        preflight = self.play("Validate explicit single-account Linux scope")
        self.assertIs(self.plays[0], preflight)
        self.assertTrue(preflight["any_errors_fatal"])
        inputs = preflight["tasks"][0]["ansible.builtin.assert"]["that"]
        for expected in ["ansible_version.full is version('2.19', '>=')",
                         "ansible_version.full is version('2.20', '<')",
                         "groups.get('linux', []) | length > 0",
                         "diskmon_inventory_settings.profile == ansible_aws_ssm_profile",
                         "diskmon_inventory_settings.regions == [aws_region]"]:
            self.assertIn(expected, inputs)
        identity = self.task(preflight["tasks"], "Verify the runtime profile identity before monitoring AWS operations")
        self.assertEqual(identity["ansible.builtin.command"]["argv"][:3], ["aws", "sts", "get-caller-identity"])
        self.assertEqual(identity["when"], "not ansible_check_mode")
        role = self.task(preflight["tasks"], "Refuse another account or runtime role")["ansible.builtin.assert"]["that"]
        self.assertIn("assumed-role/", role[1])
        self.assertIn("diskmon_runtime_role_arn", role[1])
        host_checks = self.task(preflight["tasks"], "Refuse merged or inconsistent host identities")["ansible.builtin.assert"]["that"]
        self.assertIn("hostvars[diskmon_host].placement.region == aws_region", host_checks)
        self.assertIn("hostvars[diskmon_host].state.name == 'running'", host_checks)
        self.assertNotIn("hostvars[diskmon_host].ansible_aws_ssm_profile", "\n".join(host_checks))
        self.assertIn("playbook_dir ~ '/inventory.aws_ec2.yml'", preflight["vars"]["diskmon_inventory_settings"])
        for key in ["workload_account_id", "diskmon_runtime_role_arn", "ansible_aws_ssm_bucket_name", "diskmon_alarm_topic_arn"]:
            self.assertEqual(self.settings[key], "replace-me")

    def test_configure_guard_package_json_and_handler_are_inline(self):
        linux = self.play("Configure the agent or collect Linux mount facts")
        self.assertEqual(linux["serial"], 25)
        configure = linux["tasks"][0]
        self.assertTrue(configure["become"])
        tasks = configure["block"]
        self.assertIn("ansible.builtin.wait_for_connection", tasks[0])
        self.assertIn("ansible.builtin.setup", tasks[1])
        self.assertIn("ansible_facts.distribution_major_version == '2023'", tasks[2]["ansible.builtin.assert"]["that"])
        self.assertEqual(tasks[3]["ansible.builtin.package"], {"name": "amazon-cloudwatch-agent", "state": "present"})
        self.assertIn("to_nice_json", tasks[5]["ansible.builtin.copy"]["content"])
        self.assertEqual(tasks[6]["ansible.builtin.meta"], "flush_handlers")
        self.assertEqual(tasks[7]["ansible.builtin.service"]["state"], "started")
        handler = linux["handlers"][0]
        self.assertTrue(handler["become"])
        self.assertIn("fetch-config", handler["ansible.builtin.command"]["argv"])
        self.assertIn("file:{{ diskmon_agent_config_path }}", handler["ansible.builtin.command"]["argv"])

    def test_heartbeat_precedes_disk_discovery_and_coverage(self):
        tasks = self.alarm_tasks()
        names = [task["name"] for task in tasks]
        heartbeat = self.task(tasks, "Reconcile missing-agent heartbeat alarms")["amazon.aws.cloudwatch_metric_alarm"]
        for later in ["Discover disk series with automatic AWS CLI pagination",
                      "Require a discovered disk series for every active Linux instance"]:
            self.assertLess(names.index("Reconcile missing-agent heartbeat alarms"), names.index(later))
        self.assertEqual(heartbeat["metric_name"], "mem_used_percent")
        self.assertEqual(heartbeat["comparison"], "LessThanThreshold")
        self.assertEqual(heartbeat["threshold"], 0)
        self.assertEqual(heartbeat["treat_missing_data"], "breaching")
        self.assertEqual(set(heartbeat["dimensions"]), {"InstanceId"})
        discovery = self.task(tasks, "Discover disk series with automatic AWS CLI pagination")["ansible.builtin.command"]["argv"]
        self.assertNotIn("--no-paginate", discovery)
        schema = self.task(tasks, "Validate InstanceId and the exact active-host disk dimension schema")["ansible.builtin.assert"]["that"]
        self.assertIn("['InstanceId', 'fstype', 'path']", schema[1])
        self.assertIn("diskmon_metric.Dimensions | length == 3", schema[1])

    def test_alarm_product_preserves_dimensions_and_stable_names(self):
        play = self.play("Manage workload-local disk and heartbeat alarms from the controller")
        task = self.task(self.alarm_tasks(), "Reconcile warning and critical alarms for each exact series")
        metric = {"Dimensions": [{"Name": "path", "Value": "/data"},
                                 {"Name": "InstanceId", "Value": "i-0123456789abcdef0"},
                                 {"Name": "fstype", "Value": "xfs"}]}
        severities = self.render(play["vars"]["diskmon_severities"])
        pairs = self.render(task["loop"], diskmon_target_metrics=[metric], diskmon_severities=severities)
        self.assertEqual(len(pairs), 2)
        self.assertEqual(task["loop_control"]["loop_var"], "alarm_pair")
        dimensions = self.render(task["vars"]["diskmon_dimensions"], alarm_pair=pairs[0])
        expected = {item["Name"]: item["Value"] for item in metric["Dimensions"]}
        self.assertEqual(dimensions, expected)
        expected_hash = hashlib.sha1(json.dumps([
            {"key": key, "value": expected[key]} for key in sorted(expected, key=str.casefold)
        ]).encode()).hexdigest()[:12]
        dimension_hash = self.render(task["vars"]["diskmon_dimension_hash"], diskmon_dimensions=dimensions)
        self.assertEqual(dimension_hash, expected_hash)
        for pair, severity in zip(pairs, ["warning", "critical"]):
            alarm = self.render(task["amazon.aws.cloudwatch_metric_alarm"], alarm_pair=pair,
                                diskmon_dimensions=dimensions, diskmon_dimension_hash=dimension_hash)
            self.assertEqual(alarm["dimensions"], expected)
            self.assertEqual(alarm["name"], f"diskmon-{expected['InstanceId']}-{expected_hash}-{severity}")
            self.assertEqual(alarm["threshold"], 80 if severity == "warning" else 90)
            self.assertEqual(alarm["treat_missing_data"], "missing")
            self.assertEqual(alarm["datapoints_to_alarm"], 3)
            self.assertEqual(alarm["evaluation_periods"], 5)
        metric["Dimensions"].reverse()
        reordered = self.render(task["vars"]["diskmon_dimensions"], alarm_pair=(metric, severities[0]))
        self.assertEqual(self.render(task["vars"]["diskmon_dimension_hash"], diskmon_dimensions=reordered), expected_hash)

    def test_skipped_alarm_loops_and_check_mode_are_safe(self):
        play = self.play("Manage workload-local disk and heartbeat alarms from the controller")
        self.assertIn("not ansible_check_mode", play["tasks"][0]["when"])
        for task in self.alarm_tasks():
            if "loop" in task and task["loop_control"]["loop_var"] != "diskmon_instance_id":
                self.assertEqual(list(self.render(task["loop"], diskmon_severities=[])), [])

    def test_audit_is_failure_tolerant_without_platform_guard(self):
        audit = self.play("Configure the agent or collect Linux mount facts")["tasks"][1]
        setup = audit["block"][0]
        self.assertTrue(setup["ignore_unreachable"])
        self.assertTrue(setup["ignore_errors"])
        self.assertEqual(setup["ansible.builtin.setup"]["gather_subset"], ["!all", "!min", "mounts"])
        self.assertNotIn("distribution", json.dumps(audit))
        normalize = audit["block"][1]
        for result, mounts, expected in [({"unreachable": True}, [], "unreachable"),
                                         ({"failed": True}, [], "error"), ({}, [], "error"),
                                         ({}, [{"mount": "/", "size_total": 100}], "ok")]:
            status = self.render(normalize["vars"]["diskmon_audit_status"],
                                 diskmon_mount_result=result, diskmon_real_mounts=mounts)
            self.assertEqual(status, expected)
            record = self.render(normalize["ansible.builtin.set_fact"]["diskmon_record"],
                                 diskmon_audit_status=status, diskmon_real_mounts=mounts,
                                 instance_id="i-one", ansible_aws_ssm_region="us-east-1")
            self.assertEqual(record["mounts"], mounts if expected == "ok" else [])
            self.assertEqual(record["owner"], "unassigned")

    def test_aggregate_fallback_preserves_every_host(self):
        tasks = self.report_tasks()
        aggregate = self.task(tasks, "Include every Linux host even without a collection record")
        hostvars = {"i-one": {"diskmon_record": {"instance_id": "i-one", "status": "ok"}},
                    "i-two": {"instance_id": "i-two"}, "i-three": {}}
        records = []
        for host in self.render(aggregate["loop"], groups={"linux": list(hostvars)}):
            context = {"diskmon_host": host, "hostvars": hostvars, "aws_region": "us-east-1"}
            fallback = self.render(aggregate["vars"]["diskmon_fallback"], **context)
            records = self.render(aggregate["ansible.builtin.set_fact"]["diskmon_report_hosts"],
                                  **context, diskmon_fallback=fallback, diskmon_report_hosts=records)
        self.assertEqual(len(records), 3)
        self.assertEqual(records[0], hostvars["i-one"]["diskmon_record"])
        self.assertEqual({record["instance_id"] for record in records}, set(hostvars))
        for record in records[1:]:
            self.assertEqual(record["status"], "error")
            self.assertEqual(record["mounts"], [])
            self.assertEqual(record["owner"], "unassigned")
            self.assertEqual(record["region"], "us-east-1")
            self.assertEqual(record["account_id"], self.settings["workload_account_id"])
            self.assertIn("not attempted", record["error"])
        write = self.task(tasks, "Write complete coverage input as JSON")
        document = self.render(write["ansible.builtin.copy"]["content"],
                               diskmon_collected_at="2026-10-10T12:00:00Z", diskmon_report_hosts=records)
        document = json.loads(document) if isinstance(document, str) else document
        self.assertEqual(document["source"], "aws-ssm")
        self.assertEqual(document["hosts"], records)

    def test_audit_argv_paths_thresholds_printing_and_findings(self):
        play = self.play("Assemble Linux coverage input and run the local reporter")
        self.assertIn("not ansible_check_mode", play["tasks"][0]["when"])
        tasks = self.report_tasks()
        report = self.task(tasks, "Generate reports with configured thresholds and retain findings")
        context = {"ansible_playbook_python": "/controller/python", "playbook_dir": str(ROOT / "ansible"),
                   "diskmon_report_script": str(ROOT / "ansible/scripts/disk_report.py"),
                   "diskmon_report_directory": str(ROOT / "reports")}
        argv = self.render(report["ansible.builtin.command"]["argv"], **context)
        self.assertEqual(argv[:2], [context["ansible_playbook_python"], context["diskmon_report_script"]])
        self.assertEqual(str(argv[argv.index("--warning") + 1]), "80")
        self.assertEqual(str(argv[argv.index("--critical") + 1]), "90")
        self.assertIn("--fail-on-findings", argv)
        self.assertFalse(report["changed_when"])
        self.assertEqual(report["failed_when"], "diskmon_report_result.rc not in [0, 1]")
        self.assertIn("ansible.builtin.debug", tasks[-2])
        final_gate = tasks[-1]["ansible.builtin.assert"]["that"][0]
        for code, expected in [(0, True), (1, False)]:
            self.assertEqual(self.render("{{ " + final_gate + " }}", diskmon_report_result={"rc": code}), expected)
        self.assertEqual(Path(self.render(self.settings["diskmon_report_script"], **context)).resolve(),
                         ROOT / "ansible/scripts/disk_report.py")
        self.assertEqual(Path(self.render(self.settings["diskmon_report_directory"], **context)).resolve(), ROOT / "reports")

    def test_controller_dependencies_and_config_are_retained(self):
        config = configparser.ConfigParser()
        config.read(ROOT / "ansible/ansible.cfg")
        self.assertNotIn("inventory", config["defaults"])
        self.assertNotIn("roles_path", config["defaults"])
        requirements = yaml.safe_load((ROOT / "ansible/requirements.yml").read_text())
        self.assertEqual(requirements["collections"], [{"name": "amazon.aws", "version": "11.4.0"}])
        self.assertIn("ansible-core>=2.19,<2.20", (ROOT / "ansible/requirements-controller.txt").read_text())


if __name__ == "__main__":
    unittest.main()