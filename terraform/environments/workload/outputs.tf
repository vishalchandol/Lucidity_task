output "runtime_role_arn" { value = module.workload.runtime_role_arn }
output "transfer_bucket_name" { value = module.workload.transfer_bucket_name }
output "instance_metric_policy_arn" { value = module.workload.instance_metric_policy_arn }
output "ssm_bootstrap_policy_arn" { value = module.workload.ssm_bootstrap_policy_arn }
output "alarm_topic_arn" { value = module.workload.alarm_topic_arn }
output "metric_namespace" { value = module.workload.metric_namespace }
output "oam_link_arn" { value = module.workload.oam_link_arn }