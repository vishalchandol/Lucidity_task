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
instance-ID inventory sources. Use the approved named profile for each run.

## Repeatable Enrollment

Run `configure-agent.yml`, then `alarms.yml` after discovery and metric startup.
Each playbook imports the same preflight checks. Configuration uses batches of
25, bounded controller forks and repeatable tasks.
Continuous agent publication is distributed across VMs, independent of these jobs.
Configuration retries are bounded; unreachable hosts are visible for remediation.

As a new persistent mount appears, the agent discovers it through `resources: *`;
the next metric-discovery/alarm run adds its alarms. ListMetrics can be delayed
or stale, so it does not establish freshness or a complete expected-mount list.
Keep an application-owned mount registry for stronger production coverage.

In enterprise operation, schedule per-account/Region runs using existing Ansible
controller capabilities. Review discovered hosts and failed connections after
each run; alert on controller job failure. No scheduler is installed here.
Shard the job queue, avoid overlapping jobs for one fleet, retry throttling with
backoff, and keep account failures isolated from other accounts.

## Alerts and Missing Data

| Signal | Default behavior |
| --- | --- |
| Disk warning | >=80%, Maximum, 3 of 5 one-minute periods |
| Disk critical | >=90%, Maximum, 3 of 5 one-minute periods |
| Missing disk series | `missing` treatment plus insufficient-data SNS action |
| Missing agent samples | Heartbeat alarm, missing treated as breaching |

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
is for active metric series, not a full inventory. The per-instance heartbeat
alarms provide the basic missing-agent signal; a separate audit report is not
part of this solution.