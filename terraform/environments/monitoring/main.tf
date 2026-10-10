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
    tags = { Project = "DiskMonitoring", Environment = "Monitoring" }
  }
}

module "monitoring" {
  source             = "../../modules/monitoring"
  name               = "diskmon-central-${var.aws_region}"
  source_account_ids = var.source_account_ids
}

output "sink_arn" { value = module.monitoring.sink_arn }
output "central_event_bus_arn" { value = module.monitoring.central_event_bus_arn }
output "central_topic_arn" { value = module.monitoring.central_topic_arn }
output "dashboard_name" { value = module.monitoring.dashboard_name }