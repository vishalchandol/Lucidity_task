# Terminal-Only Runbook

## Local Checks: No AWS Resources Needed

From PowerShell at the repository root:

```powershell
terraform fmt -check -recursive terraform
terraform -chdir=terraform/environments/demo init -backend=false -input=false
terraform -chdir=terraform/environments/demo validate
terraform -chdir=terraform/environments/monitoring init -backend=false -input=false
terraform -chdir=terraform/environments/monitoring validate
terraform -chdir=terraform/environments/workload init -backend=false -input=false
terraform -chdir=terraform/environments/workload validate
```

Provider/package downloads need internet; these commands do not provision AWS.

On a prepared Linux controller, use [Ansible prerequisites](../ansible/README.md):

```bash
export ANSIBLE_CONFIG=ansible/ansible.cfg
ansible-playbook -i localhost, ansible/monitoring.yml --syntax-check
```

Do **not** use dynamic AWS inventory for offline checks: inventory parsing makes
AWS API calls even during syntax/check mode. Ansible linting is recommended on
Linux but was not executed on this Windows development host.

## Optional Personal-Account Sandbox

These are instructions, not authorization or commands executed here. Agree the
account, Region, resources and budget before testing. Never target company AWS.

1. Prepare a deployment SSO profile and an existing tooling identity allowed to
   assume the runtime role. Review the Terraform variables and least-privilege
   deployment rights independently; no broad deploy policy is generated.
2. Create a local, ignored `terraform.tfvars` file in the selected environment
   directory, using its `variables.tf` as the input reference. Set the approved
   account/Region, tooling ARN, globally unique bucket and deployment profile.
   Optional EC2 creation is off by default; enable only with approved private
   subnet/security groups and working HTTPS service/package access.
3. Authenticate with `aws sso login --profile approved-deployment`, then verify
   `aws sts get-caller-identity --profile approved-deployment`. Confirm account
   ID, ARN and Region before any changing command.
4. Run `terraform -chdir=terraform/environments/demo init`, then `plan`, review
   every change and expected charges, and apply manually without auto-approval.
5. Read Terraform outputs and configure `diskmon-workload` as a role-backed
   profile. Populate matching inventory/group vars, transfer bucket and SNS ARN.
   Keep secrets outside the repository. Attach returned instance policies to
   an existing guest role only after reviewing its application permissions.
6. Confirm an SNS subscription, then run the configure and alarm commands in the
   Ansible guide. Wait for published metrics before disk reconciliation.
   Heartbeat alarms can enter ALARM before samples start; treat boot grace periods
   as an operating consideration, not an implemented suppression feature.
7. Verify agent configuration twice, actual dimensions, metrics, safe threshold
   transitions, recovery and missing telemetry. Save sanitized evidence only.
   One-account testing cannot prove OAM/cross-account authorization.
8. Delete reviewed Ansible-created demo alarms with a separately authorized
   identity, then review and run `terraform ... destroy` for disposable resources.
   The transfer bucket is intentionally not force-deleted; remove only approved
   leftover module-transfer objects if cleanup is blocked. Verify retained SNS
   subscriptions, roles, buckets, metrics retention and remaining charges.

Multi-account tests additionally use the monitoring/workload roots in separate
approved accounts, with matching regional sink/bus outputs. No pipeline is needed.