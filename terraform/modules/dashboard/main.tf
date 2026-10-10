terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

resource "aws_cloudwatch_dashboard" "disk" {
  dashboard_name = var.name
  dashboard_body = jsonencode({
    widgets = [for index, account in sort(tolist(var.account_ids)) : {
      type = "metric", x = (index % 2) * 12, y = floor(index / 2) * 6, width = 12, height = 6
      properties = {
        title  = "Disk used percent | ${account} | ${var.region}"
        region = var.region, accountId = account, view = "timeSeries", stacked = false
        period = 60, stat = "Maximum"
        yAxis  = { left = { min = 0, max = 100 } }
        metrics = [[{
          expression = "SEARCH('{Enterprise/DiskMonitoring,InstanceId,path,fstype} MetricName=\"disk_used_percent\"', 'Maximum', 60)"
          id         = "diskusage", accountId = account, region = var.region
        }]]
      }
    }]
  })
}

variable "name" { type = string }
variable "account_ids" {
  type = set(string)
  validation {
    condition     = length(var.account_ids) > 0 && alltrue([for account in var.account_ids : can(regex("^[0-9]{12}$", account))])
    error_message = "Supply explicit 12-digit dashboard source account IDs."
  }
}
variable "region" {
  type = string
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.region))
    error_message = "Supply a commercial AWS Region such as us-east-1."
  }
}
output "name" { value = aws_cloudwatch_dashboard.disk.dashboard_name }