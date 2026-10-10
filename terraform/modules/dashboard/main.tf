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
