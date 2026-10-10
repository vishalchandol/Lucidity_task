# Validation Status

This repository contains a proposed solution, not a deployed AWS service.

## Checked Locally

- Terraform formatting (`terraform fmt -check -recursive terraform`).
- Terraform initialization with `-backend=false` and `terraform validate` for
  the demo, workload and monitoring roots.
- Markdown links and Mermaid diagram syntax during document preparation.

Terraform initialization downloads providers/modules but does not create AWS
resources. No Terraform plan, apply or destroy was run.

## Not Tested In AWS

- SSM access, account trust and live IAM enforcement.
- CloudWatch Agent startup and actual emitted metric dimensions.
- Alarm state transitions, SNS delivery and subscription behavior.
- Cross-account OAM visibility and dashboard rendering against live accounts.
- Multi-account rollout behavior or fleet-scale limits.


