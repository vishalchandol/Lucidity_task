terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  profile             = var.aws_profile
  region              = var.aws_region
  allowed_account_ids = [var.account_id]
  default_tags {
    tags = { Project = "DiskMonitoring", Environment = "Workload" }
  }
}

module "workload" {
  source                = "../../modules/workload"
  name                  = "diskmon-${var.aws_region}"
  tooling_role_arn      = var.tooling_role_arn
  transfer_bucket_name  = var.transfer_bucket_name
  session_instance_tags = var.session_instance_tags
  monitoring_sink_arn   = var.monitoring_sink_arn
  central_event_bus_arn = var.central_event_bus_arn
}

output "runtime_role_arn" { value = module.workload.runtime_role_arn }
output "transfer_bucket_name" { value = module.workload.transfer_bucket_name }
output "instance_metric_policy_arn" { value = module.workload.instance_metric_policy_arn }
output "ssm_bootstrap_policy_arn" { value = module.workload.ssm_bootstrap_policy_arn }
output "alarm_topic_arn" { value = module.workload.alarm_topic_arn }
output "metric_namespace" { value = module.workload.metric_namespace }
output "oam_link_arn" { value = module.workload.oam_link_arn }