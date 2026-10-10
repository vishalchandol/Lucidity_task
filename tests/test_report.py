import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ansible" / "scripts"))
from disk_report import build_report, render_csv


class ReportTests(unittest.TestCase):
    def setUp(self):
        self.fleet = json.loads((Path(__file__).parent / "fixtures" / "fleet.json").read_text())

    def test_fleet_severity_and_coverage(self):
        report = build_report(self.fleet)
        self.assertEqual(report["summary"]["rows_by_status"],
                         {"OK": 1, "WARNING": 1, "CRITICAL": 1, "NO_DATA": 1})
        self.assertEqual(report["summary"]["covered_hosts"], 2)
        self.assertEqual(report["summary"]["hosts_with_no_data"], 1)
        self.assertEqual(report["source"], "simulated")

    def test_threshold_boundaries(self):
        mount = self.fleet["hosts"][0]["mounts"][0]
        mount.update(size_total=100, size_available=20)
        self.assertEqual(build_report(self.fleet)["rows"][0]["status"], "WARNING")
        mount["size_available"] = 10
        self.assertEqual(build_report(self.fleet)["rows"][0]["status"], "CRITICAL")

    def test_empty_inventory_is_not_healthy(self):
        self.fleet["hosts"] = []
        with self.assertRaises(ValueError):
            build_report(self.fleet)

    def test_duplicate_identity_rejected(self):
        self.fleet["hosts"].append(copy.deepcopy(self.fleet["hosts"][0]))
        with self.assertRaises(ValueError):
            build_report(self.fleet)

    def test_invalid_capacity_is_no_data(self):
        for invalid in (0, -1, float("nan"), float("inf")):
            self.fleet["hosts"][0]["mounts"][0]["size_total"] = invalid
            self.assertEqual(build_report(self.fleet)["rows"][0]["status"], "NO_DATA")

    def test_pseudo_only_host_is_no_data(self):
        for mount in self.fleet["hosts"][0]["mounts"]:
            mount["fstype"] = "tmpfs"
        self.assertEqual(build_report(self.fleet)["rows"][0]["status"], "NO_DATA")

    def test_excluded_mount_not_reported(self):
        self.assertNotIn("/run", [row["mount"] for row in build_report(self.fleet)["rows"]])

    def test_invalid_thresholds_rejected(self):
        for warning, critical in ((90, 80), (-1, 90), (80, 101)):
            with self.assertRaises(ValueError):
                build_report(self.fleet, warning, critical)

    def test_csv_neutralizes_formula_text(self):
        self.fleet["hosts"][0]["owner"] = "=HYPERLINK(bad)"
        self.assertIn("'=HYPERLINK(bad)", render_csv(build_report(self.fleet)))


if __name__ == "__main__":
    unittest.main()