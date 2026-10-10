# Discovery, Enrollment and Scaling

## Account Onboarding

Maintain an approved registry of account IDs, Regions, role ARNs and owners.
For each account/Region, apply the corresponding workload configuration only
after authorization, configure a named runtime profile, and populate reviewed
Ansible variables. Repeat the monitoring sink/link setup per Region. Accounts
outside Organizations can use the same explicit trust/onboarding procedure.

Discovery deliberately includes untagged running instances. Optional IAM session
eligibility tags restrict **access**, not inventory. An ineligible or unmanaged
VM remains a coverage gap until an owner approves its enrollment or exemption.
The workflow does not bootstrap SSM or replace existing instance profiles blindly.

Run separate jobs and state boundaries for each account/Region. Do not merge
instance-ID inventory sources. Use distinct report directories and profiles;
do not execute several writers against the same report path.

## Repeatable Enrollment

Run `monitoring.yml` with `monitoring_action=configure`, then `alarms`, then
`audit` after discovery. Each action is selected explicitly on a separate run.
Configuration uses batches of 25, bounded controller forks and repeatable tasks.
Continuous agent publication is distributed across VMs, independent of these jobs.
Configuration retries are bounded; unreachable hosts are visible for remediation.

As a new persistent mount appears, the agent discovers it through `resources: *`;
the next metric-discovery/alarm run adds its alarms. ListMetrics can be delayed
or stale, so it does not establish freshness or a complete expected-mount list.
Keep an application-owned mount registry for stronger production coverage.

In enterprise operation, schedule per-account/Region runs using existing Ansible
controller capabilities. Record expected hosts, successful enrollment and failed
hosts each run; alert on controller job failure. No scheduler is installed here.
Shard the job queue, avoid overlapping jobs for one fleet, retry throttling with
backoff, and keep account failures isolated from other accounts.

## Alerts and Missing Data

| Signal | Default behavior |
| --- | --- |
| Disk warning | >=80%, Maximum, 3 of 5 one-minute periods |
| Disk critical | >=90%, Maximum, 3 of 5 one-minute periods |
| Missing disk series | `missing` treatment plus insufficient-data SNS action |
| Missing agent samples | Heartbeat alarm, missing treated as breaching |
| Audit failure | NO_DATA row, reduced coverage and nonzero audit exit |

Both warning and critical can fire together. Confirm local and/or central SNS
subscriptions before relying on notifications. Avoid subscribing the same person
to both paths unintentionally. Stopped hosts can leave active missing-data alarms;
review maintenance and decommission events explicitly.

For low space, verify mount identity and growth, inspect log rotation/retention,
and follow an approved EBS/filesystem expansion runbook. Do not automatically
delete application data. Use an isolated disposable test volume for alarm tests,
never fill a root, controller or production filesystem.

## Retirement and Limits

Terraform does not own Ansible-created alarms. A separately authorized owner
must delete exact reviewed `diskmon-*` names for terminated demo hosts/retired
mounts. Do not delete an alarm just because a datapoint temporarily disappeared.
The runtime role deliberately lacks alarm deletion permission.

Review CloudWatch series/alarms and dashboard SEARCH limits, SSM sessions, STS
and API quotas, and OAM account/link limits before expansion. A SEARCH dashboard
is for active series, not proof that every VM was enrolled. Missing data needs
coverage reports and a production freshness reconciler, not a green-looking chart.