module "workload" {
  source                = "../../modules/workload"
  name                  = "diskmon-${var.aws_region}"
  tooling_role_arn      = var.tooling_role_arn
  transfer_bucket_name  = var.transfer_bucket_name
  session_instance_tags = var.session_instance_tags
  monitoring_sink_arn   = var.monitoring_sink_arn
  central_event_bus_arn = var.central_event_bus_arn
}
