# Validation Evidence

Status: local validation only, 2026-10-09. No AWS resources were created and no
Ansible controller run, Terraform plan/apply, Git commit or Git push was performed.

| Check | Result |
| --- | --- |
| Python reporting tests | 9 passed: coverage, thresholds, exclusions, invalid inputs and CSV safety |
| Playbook/configuration/interface checks | 16 passed after consolidation: YAML, action selection, agent settings, access guards, alarm ordering and audit handling |
| Terraform formatting | Passed recursively |
| Terraform demo/workload/monitoring initialization | Passed, backend disabled, provider download only |
| Terraform validate | Passed for all three roots |
| Fixture CLI report | Passed: 3 expected hosts, 2 covered, 1 no-data; one row in each severity |
| Native Ansible syntax/execution/lint | Not run: Linux/WSL controller unavailable |
| SSM connectivity and IAM denial tests | Not run in AWS |
| Agent runtime schema, publication and idempotency | Not run in AWS |
| Disk/heartbeat alarm transitions and SNS delivery | Not run in AWS |
| OAM cross-account visibility | Not run in AWS |
| Windows monitoring | Not implemented; inventory visibility only |
| Public repository accessibility | Confirmed; new files remain local/uncommitted |

Tools: Windows, Python 3.14.5 for local development, Terraform 1.13.1,
AWS provider 6.68.0, PyYAML 6.0.3, Jinja2 3.1.6. The Linux controller requirements
are separate (Python 3.11-3.13, ansible-core 2.19.x, amazon.aws 11.4.0).

Static tests cannot prove guest collection, real IAM enforcement, actual metric
dimension emission or end-to-end notification delivery. These limitations are
explicit so the submission does not present fixture output as live-cloud evidence.