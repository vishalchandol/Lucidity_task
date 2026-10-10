output "runtime_role_arn" { value = aws_iam_role.runtime.arn }
output "transfer_bucket_name" { value = aws_s3_bucket.transfer.id }
output "instance_metric_policy_arn" { value = aws_iam_policy.instance_metrics.arn }
output "ssm_bootstrap_policy_arn" { value = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore" }
output "alarm_topic_arn" { value = aws_sns_topic.alarms.arn }
output "metric_namespace" { value = local.namespace }
output "oam_link_arn" { value = try(aws_oam_link.metrics[0].arn, null) }