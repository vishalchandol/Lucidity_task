output "runtime_role_arn" { value = module.workload.runtime_role_arn }
output "transfer_bucket_name" { value = module.workload.transfer_bucket_name }
output "instance_metric_policy_arn" { value = module.workload.instance_metric_policy_arn }
output "ssm_bootstrap_policy_arn" { value = module.workload.ssm_bootstrap_policy_arn }
output "alarm_topic_arn" { value = module.workload.alarm_topic_arn }
output "metric_namespace" { value = module.workload.metric_namespace }
output "dashboard_name" { value = module.dashboard.name }
output "demo_instance_id" { value = try(aws_instance.demo[0].id, null) }