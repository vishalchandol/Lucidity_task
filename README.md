# Scalable AWS Disk Monitoring

This solution uses Ansible to configure disk monitoring on EC2 instances across
AWS accounts. CloudWatch Agent collects filesystem metrics continuously, and
CloudWatch provides alarms and dashboards. Terraform defines the supporting
access and monitoring resources.

Repository: https://github.com/vishalchandol/Lucidity_task

## Architecture

[Architecture diagram and numbered execution flow](docs/architecture.md)
are available in Markdown and as a [Word document](docs/architecture-cloudwatch.docx).

The design separates configuration from monitoring: Ansible configures the VMs,
but metric collection continues even when the controller is unavailable. Default
EC2 and EBS metrics do not expose guest filesystem free space, which is why the
CloudWatch Agent is needed.

## Assignment Deliverables

For direct answers to the access, collection/aggregation, and scalability
questions, see [Direct Answers to the Assignment](docs/solution-answers.md).

| Deliverable | Files |
| --- | --- |
| High-level architecture | [Architecture and flow diagrams](docs/architecture.md) |
| Collection and alarms | [Monitoring playbook](ansible/monitoring.yml) configures the agent and alarms |
| Aggregation and presentation | CloudWatch metrics and [account-level dashboards](terraform/modules/dashboard/main.tf) |
| Access management | [Workload IAM resources](terraform/modules/workload/main.tf) and [connection settings](ansible/settings.yml) |
| VM discovery and enrollment | [EC2 inventory](ansible/inventory.aws_ec2.yml), with configure and alarms actions in the monitoring playbook |
| Scaling to more accounts and VMs | [Account onboarding and operations](docs/operations.md) |

## How It Works

1. **Access:** Use SSO and an assumed workload role. Ansible connects through
   Systems Manager, without opening SSH ports. A private encrypted S3 bucket
   holds temporary module transfers. Existing application instance roles are preserved.
2. **Discovery and enrollment:** Discover running VMs, including untagged ones,
   then configure supported Linux hosts in batches of 25. Repeat the same runs
   for each account/Region; heartbeat alarms detect missing agent metrics.
3. **Collection and alerts:** Publish disk utilization and free/total space every
   60 seconds. Warning and critical thresholds are 80% and 90%, evaluated over
   3 of 5 periods. A heartbeat alarm detects missing agent samples.
4. **Aggregation and alerts:** CloudWatch stores and presents the metrics in
   account-level dashboards; regional OAM links provide cross-account visibility.
   SNS sends alarm notifications; central event forwarding is optional.
5. **Growth:** Refresh inventory and rerun enrollment and alarm setup for new
   VMs. Keep account/Region jobs separate. Use the existing Ansible
   scheduler in production; no pipeline or new scheduler is included here.

## Run And Validate

For AWS use, [one Ansible playbook](ansible/monitoring.yml) provides explicit
`configure` and `alarms` actions. See [the Ansible guide](ansible/README.md) for
Linux/WSL controller setup and [the terminal runbook](docs/terminal-runbook.md)
for Terraform formatting and validation commands. These local Terraform checks
do not create AWS resources. Sandbox testing is optional and must use an approved
personal account, never company AWS.

## Setup and Limitations

 [Local and AWS validation status](docs/validation.md).

Agent installation currently targets Amazon Linux 2023; Windows VMs are discovered
but not configured. Ansible needs a Linux/WSL controller. Terraform validation
has passed locally; live SSM access, agent publication, alarm delivery and
cross-account visibility have not been tested.

No company-cloud deployment is required. Keep credentials, state, private
inventory and generated reports out of the public repository.
