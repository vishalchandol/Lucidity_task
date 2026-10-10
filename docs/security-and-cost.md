# Security and Cost

## Identity Boundaries

| Identity | Responsibility |
| --- | --- |
| Operator/deployment role | Manually provision approved resources; separate from runtime role |
| Tooling identity | Assume only approved workload runtime roles |
| Workload runtime role | Regional inventory, eligible SSM sessions, transient S3 transfers and `diskmon-*` alarm updates |
| EC2 instance role | SSM registration and namespace-restricted metric publication; preserve application permissions |
| EventBridge forwarding role | Publish events only to the designated central bus |
| Central delivery role | Publish only to central SNS, trusted by the exact central rule |

Use SSO/STS, never committed keys. Read-only discovery APIs and PutMetricData
require wildcard resource scope; Region/namespace conditions narrow their use.
SSM session access is guest administration, not a command sandbox: it may expose
application/instance credentials. Review the blast radius before granting it.

Module transfers use presigned URLs authorized by the controller. Instances
need HTTPS access to S3 but do not require S3 IAM grants. Block public access,
enforce TLS and encryption, keep the dedicated bucket unversioned, and expire
interrupted transfer objects. Lifecycle cleanup is asynchronous. Review endpoint
policies so they do not deny the signed transfers. Do not enable verbose secret
logging or publish real reports, state, credentials or private inventory.

AWS-managed SSM permissions are a documented bootstrap convenience, not a claim
of a fully minimized production policy. OAM filters metrics on each source link;
the sink's resource-type permission cannot enforce namespace filtering against
an approved source administrator. Review link changes and trust principals.

## Network and Reliability

Use existing private networking with HTTPS access to required regional SSM,
ssmmessages, CloudWatch and S3 services plus approved package repositories.
No new inbound SSH/RDP or public IP is needed. This example does not provision
VPC endpoints/NAT, session logging, event delivery DLQs or failure alarms.
Production should add those with workload-specific policies and retention.

## Cost Model

For N instances and M average persistent mounts, baseline metric cardinality is
approximately `N * (3 * M + 1)` (three disk metrics and one memory heartbeat).
Alarm count is approximately `N * (2 * M + 1)` (warning, critical and heartbeat).
Additional dimensions/aggregation can increase series count; exclusions and
low-resolution defaults must not hide application data volumes.

Estimate current regional CloudWatch metric, alarm, dashboard and API-query
prices, S3/SSM usage, SNS/EventBridge, and existing endpoint/NAT costs. Do not
claim CloudWatch monitoring is free because the agent has no license fee.
Keep one-minute resolution, avoid unnecessary logs/series, batch controller work,
and review abandoned alarms/resources. No monthly total is meaningful without
fleet size, Regions, mounts and current AWS pricing.

## Public Repository Hygiene

Ignored: virtual environments, provider caches, private variable files, state,
plans, credentials and generated reports. Commit provider lock files and sanitized
examples only. Review `git status` and perform an organization-approved secret
scan before publishing. No automated secret scanner was run in this implementation.