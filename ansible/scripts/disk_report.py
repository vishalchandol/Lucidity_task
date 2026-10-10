"""Aggregate Ansible filesystem facts into a JSON and CSV disk report."""

import argparse
import csv
import io
import json
import math
from pathlib import Path


EXCLUDED_FILESYSTEMS = {
    "proc", "sysfs", "tmpfs", "devtmpfs", "overlay", "squashfs", "cgroup",
    "cgroup2", "debugfs", "securityfs", "pstore", "tracefs", "configfs",
    "devpts", "mqueue", "hugetlbfs", "fusectl", "autofs", "binfmt_misc", "nsfs", "ramfs",
}


def build_report(fleet, warning=80, critical=90):
    if not 0 <= warning < critical <= 100:
        raise ValueError("Thresholds must satisfy 0 <= warning < critical <= 100")
    hosts = fleet["hosts"]
    if not hosts:
        raise ValueError("Empty inventory is not evidence of healthy coverage")
    rows = []
    identities = set()
    counts = {"OK": 0, "WARNING": 0, "CRITICAL": 0, "NO_DATA": 0}
    covered_hosts = 0
    for host in hosts:
        identity = tuple(str(host[field]) for field in ("account_id", "region", "instance_id"))
        if identity in identities:
            raise ValueError("Duplicate host identity: " + "/".join(identity))
        identities.add(identity)
        base = dict(zip(("account_id", "region", "instance_id"), identity))
        base["owner"] = host.get("owner", "unassigned")
        host_rows = []
        if host.get("status") == "ok":
            seen_mounts = set()
            for mount in host.get("mounts", []):
                if mount.get("fstype") in EXCLUDED_FILESYSTEMS:
                    continue
                path = mount.get("mount", "unknown")
                if path in seen_mounts:
                    raise ValueError("Duplicate mount: " + path)
                seen_mounts.add(path)
                row = {**base, "mount": path, "fstype": mount.get("fstype", "unknown")}
                try:
                    total = float(mount["size_total"])
                    available = float(mount["size_available"])
                    if not math.isfinite(total) or not math.isfinite(available):
                        raise ValueError("Non-finite capacity")
                    if total <= 0 or not 0 <= available <= total:
                        raise ValueError("Invalid capacity")
                    used = 100 * (1 - available / total)
                    status = "CRITICAL" if used >= critical else "WARNING" if used >= warning else "OK"
                    row.update(status=status, used_percent=round(used, 2),
                               free_gib=round(available / 1024 ** 3, 2), error="")
                except (KeyError, TypeError, ValueError) as error:
                    row.update(status="NO_DATA", used_percent=None, free_gib=None, error=str(error))
                host_rows.append(row)
        if not host_rows:
            host_rows.append({**base, "mount": "", "fstype": "", "status": "NO_DATA",
                              "used_percent": None, "free_gib": None,
                              "error": host.get("error") or "No persistent filesystem data"})
        if all(row["status"] != "NO_DATA" for row in host_rows):
            covered_hosts += 1
        for row in host_rows:
            counts[row["status"]] += 1
        rows.extend(host_rows)
    return {
        "source": fleet.get("source", "unspecified"),
        "collected_at": fleet.get("collected_at", "unspecified"),
        "thresholds": {"warning": warning, "critical": critical},
        "summary": {"expected_hosts": len(hosts), "covered_hosts": covered_hosts,
                    "hosts_with_no_data": len(hosts) - covered_hosts, "rows_by_status": counts},
        "rows": rows,
    }


def render_csv(report):
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=["account_id", "region", "instance_id", "owner",
                                             "mount", "fstype", "status", "used_percent", "free_gib", "error"])
    writer.writeheader()
    for original in report["rows"]:
        row = dict(original)
        for field, value in row.items():
            if isinstance(value, str) and value.lstrip().startswith(("=", "+", "-", "@")):
                row[field] = "'" + value
        writer.writerow(row)
    return stream.getvalue()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, default=Path("reports"))
    parser.add_argument("--warning", type=float, default=80)
    parser.add_argument("--critical", type=float, default=90)
    parser.add_argument("--fail-on-findings", action="store_true")
    arguments = parser.parse_args()
    try:
        fleet = json.loads(arguments.input.read_text(encoding="utf-8"))
        report = build_report(fleet, arguments.warning, arguments.critical)
    except (OSError, KeyError, TypeError, ValueError) as error:
        parser.error(str(error))
    arguments.output_dir.mkdir(parents=True, exist_ok=True)
    (arguments.output_dir / "disk-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    (arguments.output_dir / "disk-report.csv").write_text(render_csv(report), encoding="utf-8", newline="")
    print(json.dumps({"source": report["source"], **report["summary"]}, indent=2))
    findings = report["summary"]["rows_by_status"]
    if arguments.fail_on_findings and any(findings[status] for status in ("WARNING", "CRITICAL", "NO_DATA")):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())