output "sink_arn" { value = aws_oam_sink.metrics.arn }
output "central_event_bus_arn" { value = aws_cloudwatch_event_bus.alerts.arn }
output "central_topic_arn" { value = aws_sns_topic.alerts.arn }
output "dashboard_name" { value = module.dashboard.name }