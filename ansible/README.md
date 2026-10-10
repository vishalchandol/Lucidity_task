# Linux Disk Monitoring

[monitoring.yml](monitoring.yml) has four plays: preflight, Linux configuration or
mount collection, controller alarms, and controller audit aggregation. Every play
loads [settings.yml](settings.yml). Only the explicitly selected action runs;
omitting `monitoring_action` or using another value fails preflight.

## Controller And Settings

Use Linux/WSL with Python 3.11-3.13, ansible-core 2.19.x and amazon.aws 11.4.0.
Native Windows is not an Ansible controller. Install AWS CLI v2 and
`session-manager-plugin` in the same environment. From the repository root:

```bash
python3 -m venv .venv-controller
. .venv-controller/bin/activate
python -m pip install -r ansible/requirements-controller.txt
export ANSIBLE_CONFIG=ansible/ansible.cfg
ansible-galaxy collection install -r ansible/requirements.yml
```

Replace the account, runtime role ARN, transfer bucket and SNS placeholders in
[settings.yml](settings.yml) with the workload values supplied by Terraform.
Quote the 12-digit account ID. Set the inventory profile/Region to match SSM.
Use one role-backed profile for inventory, SSM, CLI and CloudWatch modules:

```ini
[profile diskmon-workload]
role_arn = <runtime_role_arn output>
source_profile = approved-tooling-sso
role_session_name = diskmon-ansible
region = us-east-1
```

The runtime role needs the existing SSM/S3/CloudWatch permissions; it is not the
Terraform deployment identity. Hosts need Python 3, curl, SSM Agent, instance-role
SSM/metric permissions and network access to SSM, S3, CloudWatch and package sources.
Transfers use controller-signed URLs and `AWS-StartInteractiveCommand`; no instance
S3 policy is needed. Use the dedicated regional, unversioned transfer bucket.

## Select One Action

Run from the repository root after configuring the profile and settings:

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook -i ansible/inventory.aws_ec2.yml ansible/monitoring.yml -e monitoring_action=configure
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook -i ansible/inventory.aws_ec2.yml ansible/monitoring.yml -e monitoring_action=alarms
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook -i ansible/inventory.aws_ec2.yml ansible/monitoring.yml -e monitoring_action=audit
```

Inventory discovers all running instances, including untagged hosts. Windows stays
visible in its own group but is not configured or audited. Instance IDs are SSM
targets. Do not merge accounts/Regions, exclude localhost, or bypass preflight with
`--limit`, tags or task selection. Inventory discovery precedes preflight; subsequent
AWS operations require STS to match the declared account and assumed runtime role.

`configure` alone escalates privileges, waits for SSM, gathers facts and installs
the repository package on AL2023 x86_64/aarch64 in batches of 25. Package or JSON
changes trigger inline `fetch-config`; the service is then enabled and started.
The settings dictionary collects disk and memory metrics every 60 seconds, with
InstanceId and no hostname/device dimensions. Review the filesystem exclusions.

`alarms` installs missing-agent memory heartbeats before paginated disk discovery.
Exact disk dimensions (`InstanceId`, `path`, `fstype`) are preserved; names retain
the sorted-dimension SHA1 suffix. Defaults are 80/90%, Maximum, >=, 3 of 5 periods,
with missing disk data `missing`. Heartbeats use < 0 and missing data `breaching`.
Wait at least 15 minutes after initial configuration for disk discovery. Every
active Linux host needs a disk series. Discovery is not a freshness or mount check.
SNS notifications need confirmed subscriptions. Retired alarms are not deleted.

`audit` gathers only mount facts without the AL2023 installation restriction.
Failed, unreachable and unattempted hosts remain in the full Linux coverage input.
[scripts/disk_report.py](scripts/disk_report.py) is invoked with the controller
Python and configured thresholds. Output defaults to `reports/input.json`,
`reports/disk-report.json` and `reports/disk-report.csv`; paths are relative to the
playbook, not the working directory. Results are printed before findings fail the
audit (reporter exit 1). Use separate report directories and avoid concurrent writers.

## Offline Validation

Run `python -B -m unittest discover -s tests -v` for parsing/rendering and reporter
tests. On Linux/WSL, use `ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook -i
'localhost,' ansible/monitoring.yml --syntax-check` for offline native syntax checks.
Do not use the AWS inventory for offline checks: even `--syntax-check` discovers
instances. `--check` skips STS, alarm operations and reporting, but AWS inventory
still performs discovery. Local checks do not prove live IAM, SSM, idempotence,
published metrics or notification delivery. No deployment is implied.