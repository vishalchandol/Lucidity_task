# Direct Answers to the Assignment

## Proposed Scope

This is an AWS design and code example, not a deployed enterprise service. It
covers EC2 in separate AWS accounts and Regions. The current Ansible
configuration implementation supports Amazon Linux 2023 on x86_64/aarch64;
Windows instances may appear in discovery but are not configured or monitored
by this implementation.

## 1. Ease of Access and Management

### How are VMs managed across multiple accounts?

Use AWS IAM Identity Center (SSO) for operator authentication. From the approved
tooling identity, assume a dedicated workload runtime role in the target account.
Terraform defines that role and its trust relationship to the explicitly named
tooling role. The Terraform deployment identity is separate from the Ansible
runtime identity.

For safety and clear ownership, run Ansible separately for each account and
Region with a matching named AWS profile. The playbook checks the selected
account, assumed role, Region, and discovered instance identities before it
configures agents or changes alarms. The EC2 inventory discovers all running
instances in its configured account and Region, including untagged instances;
it does not silently rely on opt-in tags.

This is repeatable multi-account onboarding, not automatic AWS Organizations
discovery. To add an account, provision its workload resources, grant the
approved tooling role trust, configure its profile/settings, then run the same
playbook for that account and Region. Cross-account visibility uses explicit
source-account configuration in the monitoring account.

### How does Ansible connect securely and reliably?

The controller connects using AWS Systems Manager Session Manager through the
`amazon.aws.aws_ssm` connection plugin. No inbound SSH/RDP rule or long-lived
host key is needed. The EC2 host must have SSM Agent, an instance profile,
Python and `curl`, and network access to SSM, S3, CloudWatch and package sources.

Ansible's SSM plugin transfers its temporary modules through a dedicated S3
bucket. The bucket blocks public access, requires TLS, encrypts objects and
expires old transfers. The controller has the bucket transfer permissions;
instances use presigned URLs and do not need an S3 IAM grant for these transfers.
The selected SSM document and account/Region are checked before use.

The workload instance policy permits CloudWatch metric publishing only in the
chosen namespace and Region. For existing production instances, review and attach
that policy to the existing EC2 role without replacing application permissions.
The optional demo creates a separate role for its disposable instance.

## 2. Data Collection and Aggregation

### How is disk usage collected from all VMs?

Ansible installs and configures CloudWatch Agent on supported Linux instances.
The agent then collects filesystem `used_percent`, `free`, and `total` metrics
every 60 seconds, independent of Ansible controller availability. Metrics use a
dedicated namespace and filesystem dimensions (`InstanceId`, path, and filesystem
type). Temporary and pseudo filesystems are excluded by policy.

Ansible discovers the published disk metric series and creates or updates
warning and critical CloudWatch alarms for each filesystem. Current defaults are
80% and 90%, evaluated over 3 of 5 one-minute periods. It also creates a
heartbeat alarm per discovered Linux VM to flag missing agent samples. These
alarms are created by running the Ansible `alarms` action; the repository does
not configure a deployment pipeline or automatic event-triggered enrollment.

### How are metrics centralized and presented?

CloudWatch stores the metrics in the workload account and Region where each
agent publishes them. A CloudWatch dashboard presents account/Region metrics.
For multi-account visibility, the proposal uses regional CloudWatch OAM links
from workload accounts to a monitoring-account sink and dashboard. OAM provides
visibility; it does not copy the metrics into the monitoring account. Create
the sink/link arrangement in each Region being monitored.

Workload-local SNS topics receive alarm and recovery notifications. Optional
EventBridge forwarding sends selected alarm-state events to the monitoring
account. SNS subscribers must be configured and confirmed before people receive
notifications.

There is no separate Python fleet-report script in this solution. CloudWatch is
the metrics aggregation and presentation path. A CloudWatch dashboard displays
published series; it does not by itself prove that every expected VM is enrolled.
The per-VM heartbeat alarms help reveal missing agent data.

## 3. Scalability

### How does the design grow as accounts and VMs are added?

- **Additional VMs:** Dynamic inventory finds running instances without a
  manually maintained host list. Rerun the `configure` action to enroll a new
  supported VM, then wait for metric publication and run `alarms` to add its
  alarms. Configuration is batched in groups of 25.
- **Additional accounts and Regions:** Use the same workload Terraform root and
  Ansible configuration for each approved account/Region. Keep named profiles,
  state and operational runs distinct so one account's credentials or resource
  names are not accidentally used in another.
- **Metric collection:** Once configured, each agent publishes directly to
  CloudWatch. Collection does not pass through or depend on a central Ansible
  controller poll every minute.
- **Central view:** Add each approved source account and matching regional OAM
  link to the monitoring setup. The dashboard groups visibility by account and
  Region. OAM is regional, and account, dashboard, metric-series and service
  quotas/costs need review as the fleet grows.
- **Operations:** Use the enterprise's existing Ansible scheduler to repeat
  per-account/Region configuration and alarm reconciliation. This example does
  not include its own scheduler, event-driven enrollment, or organization-wide
  account discovery.

The design reduces manual host inventory work, but account onboarding remains
an explicit, reviewed step. Fleet-scale performance and AWS integration have
not been load-tested in a live environment.

## Deliverable Map

- Architecture and numbered execution flow: [architecture.md](architecture.md)
- Main Ansible actions and access checks: [monitoring.yml](../ansible/monitoring.yml)
- Dynamic EC2 inventory and runtime settings: [inventory](../ansible/inventory.aws_ec2.yml), [settings](../ansible/settings.yml)
- Terraform account roles, transfer bucket, OAM, dashboards and notifications: [Terraform guide](../terraform/README.md)
- Setup and terminal commands: [terminal runbook](terminal-runbook.md)
- Security, cost and operating details: [security and cost](security-and-cost.md), [operations](operations.md)

## Validation Status

Terraform formatting, initialization without a backend, and configuration
validation can be run locally without creating AWS resources. Live SSM access,
agent metric publication, alarm delivery, cross-account OAM visibility, and
multi-account scale have not been verified in AWS. Do not present this proposal
or its static checks as a live deployment test.