# Terraform: AWS Disk Monitoring Support

Terraform supplies IAM, transfer storage, SNS, dashboards and optional cross-account
visibility/routing. Ansible configures agents, manages disk/heartbeat alarms and
produces reports. This undeployed example has no pipeline, scheduler or Lambda.

## Roots And Modules

| Root | Scope |
| --- | --- |
| [environments/demo](environments/demo/main.tf) | Single-account runtime role, bucket, local SNS and dashboard; optional AL2023 host, `create_demo_instance = false`. No OAM/central forwarding. |
| [environments/monitoring](environments/monitoring/main.tf) | Regional OAM sink/policy, EventBridge bus/rule, central SNS and source-account dashboard widgets. |
| [environments/workload](environments/workload/main.tf) | Runtime role, bucket, local SNS and attachable metric policy; optional OAM link/forwarding. No instance creation or application-role replacement. |

Modules are `modules/workload`, `modules/monitoring` and `modules/dashboard`.
Root names include Region for account-global IAM/dashboard names. Demo and workload
are alternative fleet setups; Ansible, not Terraform, owns dynamic disk alarms.

## Inputs And Deployment Boundary

Terraform >= **1.10** and registry access are required. AWS provider constraint
is `~> 6.0`; all roots were locally validated with Terraform **1.13.1** on Windows/provider
**6.68.0**. Retain root lock files. Static checks do not prove AWS authorization or delivery.

All roots require a named **deployment** `aws_profile` and approved 12-digit `account_id`;
`aws_region` defaults to `us-east-1`. Providers enforce `allowed_account_ids = [var.account_id]`.
These target the commercial `aws` partition. No backend is configured; deployments need
protected state per account/Region and reviewed provisioning permissions.

| Root | Additional inputs |
| --- | --- |
| Demo | `tooling_role_arn`, globally unique `transfer_bucket_name`; `create_demo_instance = false`, `subnet_id = null`, `security_group_ids = []`. |
| Monitoring | Nonempty `source_account_ids`, explicit approved accounts distinct from the monitoring account. |
| Workload | `tooling_role_arn`, globally unique `transfer_bucket_name`; `session_instance_tags = { Monitoring = "enabled" }`; `monitoring_sink_arn = null`, `central_event_bus_arn = null`. |

The sanitized `terraform.tfvars.example` files contain fictional accounts, not credentials.
Deployment and runtime identities are distinct: existing tooling assumes `runtime_role_arn`,
not for provisioning. Trust names `tooling_role_arn`, not an account root. Terraform
does not create local profiles, inventory settings or notification subscriptions.

## Outputs And Ansible Interface

| Output | Consumer |
| --- | --- |
| `runtime_role_arn` | Role-backed Ansible profile `diskmon-workload`. |
| `transfer_bucket_name` | `ansible_aws_ssm_bucket_name`. |
| `instance_metric_policy_arn` | Attach to existing EC2 roles, preserving application policies and instance profiles. |
| `ssm_bootstrap_policy_arn` | Optional AWS-managed `AmazonSSMManagedInstanceCore` bootstrap attachment. |
| `alarm_topic_arn` | Workload-local `diskmon_alarm_topic_arn`. |
| `metric_namespace` | `diskmon_metric_namespace`, `Enterprise/DiskMonitoring`. |
| `oam_link_arn` | Workload-only optional link; null when disabled. |
| `dashboard_name` | Demo/monitoring dashboard. |
| `demo_instance_id` | Demo-only host; null by default. |
| `sink_arn`, `central_event_bus_arn`, `central_topic_arn` | Monitoring outputs for source integration and central subscriptions. |

Use the same runtime profile/Region for inventory, SSM and local alarm modules:

```ini
[profile diskmon-workload]
role_arn = <runtime_role_arn output>
source_profile = approved-tooling-sso
role_session_name = diskmon-ansible
region = us-east-1
```

Map `account_id` to quoted `workload_account_id`, `aws_region` to inventory
`regions`/`ansible_aws_ssm_region`. The Linux/WSL controller/plugin share this profile.
See the [Ansible guide](../ansible/README.md).

## Access, Transfer Storage And Demo

Runtime discovery/metric reads require `Resource = "*"`, scoped by requested
Region. `PutMetricAlarm` is restricted to regional `diskmon-*` alarm ARNs;
`DeleteAlarms` is intentionally absent. Local SNS accepts the account/Region's
`diskmon-*` CloudWatch alarms. Confirm subscriptions before expecting delivery.
The instance policy permits `PutMetricData` only in the selected Region/namespace,
with wildcard resource scope; it cannot constrain dimensions or prevent forged
samples. Workload outputs do not automatically attach policies to existing roles.

StartSession is limited to account/Region EC2 hosts and `AWS-StartInteractiveCommand`.
Session tags require all configured matches; an empty map removes only that tag
boundary. Tags do not filter inventory. Session cleanup/data-channel grants are
caller-session scoped and need live testing. Runtime grants exclude SendCommand,
ResumeSession, PassRole and IAM mutation. Interactive guest access is privileged,
not a command sandbox; no session logging is provisioned here.

The dedicated transfer bucket uses AES256 encryption, blocked public access,
mandatory TLS and one-day object/incomplete-upload lifecycle cleanup. It is
unversioned; do not reuse version history or enable versioning externally.
Ansible normally deletes transfers; lifecycle cleanup is asynchronous. Only the
controller role gets S3 transfer permissions; instances use presigned URLs and
need no S3 IAM policy. `force_destroy = false`: empty residual objects before
bucket destruction, allowing lifecycle time or using authorized cleanup.

Optional demo EC2 is `t3.micro`, with encrypted root disk, IMDSv2 and `Purpose = DiskMonitoringDemo`.
It attaches metric/SSM bootstrap policies to its own role. Supply an existing subnet
and security group without inbound administration rules. No VPC, NAT, endpoint,
security group, inbound rule or public IP is created/requested. HTTPS egress is required;
AL2023 supplies SSM Agent, Ansible installs CloudWatch Agent.

## Optional Cross-Account Monitoring

Create monitoring first, then workload roots: pass `sink_arn` as `monitoring_sink_arn`
and `central_event_bus_arn` as the same-named input. Both integrations default to null
and are independent. Repeat per Region. OAM links use a different account's same-Region
sink; AWS allows **one sink per account/Region**, so reuse existing sinks where necessary.

The sink permits explicit source accounts and only `AWS::CloudWatch::Metric`, with
a non-null resource-type condition. Links filter `Namespace = 'Enterprise/DiskMonitoring'`;
the sink cannot enforce this filter against source-admin changes. OAM grants visibility,
not copies. Link creation needs deployment permissions. Dashboard widgets specify source
`accountId`/`region` and SEARCH the exact disk schema, not host enrollment; limits bound fleet size.

EventBridge forwarding is separate and same-Region. Source/central rules check
account, Region, `aws.cloudwatch`, alarm-state event type, `diskmon-*` names and
ALARM/OK/INSUFFICIENT_DATA states. A source role can PutEvents only to the supplied
bus; the bus policy permits explicit source accounts and alarm-event bus invocations.
The central SNS target uses an execution role with `sns:Publish` on that topic;
SourceAccount/SourceArn conditions scope role assumption, not SNS publish calls.
The original event retains account, Region, alarm name, reason and state. There is
no DLQ/custom retry policy; DLQ and delivery-failure monitoring are production extensions.

## Static Validation

From the repository root, without AWS credentials or real variable files:

```powershell
terraform fmt -recursive terraform
terraform fmt -check -recursive terraform
terraform -chdir=terraform/environments/demo init -backend=false -input=false
terraform -chdir=terraform/environments/demo validate -no-color
terraform -chdir=terraform/environments/monitoring init -backend=false -input=false
terraform -chdir=terraform/environments/monitoring validate -no-color
terraform -chdir=terraform/environments/workload init -backend=false -input=false
terraform -chdir=terraform/environments/workload validate -no-color
```

These check local dependencies/schemas, not AWS resources; no plan/apply/destroy is needed.
See the [overview](../README.md), [terminal runbook](../docs/terminal-runbook.md),
[operations](../docs/operations.md), [security and cost](../docs/security-and-cost.md) and [validation](../docs/validation.md).