terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  namespace = "Enterprise/DiskMonitoring"
  account   = data.aws_caller_identity.current.account_id
  region    = data.aws_region.current.region
  partition = data.aws_partition.current.partition
}

resource "aws_iam_role" "runtime" {
  name = "${var.name}-runtime"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRole"
      Principal = { AWS = var.tooling_role_arn }
    }]
  })
}

resource "aws_s3_bucket" "transfer" {
  bucket        = var.transfer_bucket_name
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "transfer" {
  bucket                  = aws_s3_bucket.transfer.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "transfer" {
  bucket = aws_s3_bucket.transfer.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "transfer" {
  bucket = aws_s3_bucket.transfer.id
  rule {
    id     = "expire-transfers"
    status = "Enabled"
    filter { prefix = "" }
    expiration { days = 1 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}

resource "aws_s3_bucket_policy" "transfer" {
  bucket = aws_s3_bucket.transfer.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport", Effect = "Deny", Principal = "*", Action = "s3:*"
      Resource  = [aws_s3_bucket.transfer.arn, "${aws_s3_bucket.transfer.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

resource "aws_iam_role_policy" "runtime" {
  role = aws_iam_role.runtime.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DiscoveryAndMetricReads", Effect = "Allow"
        Action    = ["ec2:DescribeInstances", "ec2:DescribeTags", "ssm:DescribeInstanceInformation", "cloudwatch:ListMetrics", "cloudwatch:GetMetricData", "cloudwatch:DescribeAlarms"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = local.region } }
      },
      {
        Sid      = "ManagedInstanceSessions", Effect = "Allow", Action = "ssm:StartSession"
        Resource = "arn:${local.partition}:ec2:${local.region}:${local.account}:instance/*"
        Condition = merge(
          { Bool = { "ssm:SessionDocumentAccessCheck" = "true" } },
          length(var.session_instance_tags) == 0 ? {} : {
            StringEquals = { for key, value in var.session_instance_tags : "ssm:resourceTag/${key}" => value }
          }
        )
      },
      {
        Sid      = "InteractiveDocument", Effect = "Allow", Action = "ssm:StartSession"
        Resource = "arn:${local.partition}:ssm:${local.region}::document/AWS-StartInteractiveCommand"
      },
      {
        Sid       = "TerminateOwnRegionalSessions", Effect = "Allow", Action = "ssm:TerminateSession"
        Resource  = "arn:${local.partition}:ssm:${local.region}:${local.account}:session/*"
        Condition = { StringEquals = { "ssm:resourceTag/aws:ssmmessages:session-id" = "$${aws:userid}" } }
      },
      {
        Sid      = "OpenOwnSessionDataChannel", Effect = "Allow", Action = "ssmmessages:OpenDataChannel"
        Resource = "arn:${local.partition}:ssm:${local.region}:${local.account}:session/$${aws:userid}-*"
      },
      {
        Sid      = "DiskAlarmMutation", Effect = "Allow", Action = "cloudwatch:PutMetricAlarm"
        Resource = "arn:${local.partition}:cloudwatch:${local.region}:${local.account}:alarm:diskmon-*"
      },
      {
        Sid      = "ControllerBucketMetadata", Effect = "Allow", Action = ["s3:GetBucketLocation", "s3:ListBucket"]
        Resource = aws_s3_bucket.transfer.arn
      },
      {
        Sid      = "ControllerModuleTransfers", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.transfer.arn}/*"
      }
    ]
  })
}

resource "aws_iam_policy" "instance_metrics" {
  name = "${var.name}-instance-metrics"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "cloudwatch:PutMetricData", Resource = "*"
      Condition = { StringEquals = { "cloudwatch:namespace" = local.namespace, "aws:RequestedRegion" = local.region } }
    }]
  })
}

resource "aws_sns_topic" "alarms" { name = "${var.name}-alarms" }

resource "aws_sns_topic_policy" "alarms" {
  arn = aws_sns_topic.alarms.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "OnlyRegionalDiskAlarms", Effect = "Allow", Principal = { Service = "cloudwatch.amazonaws.com" }
      Action = "sns:Publish", Resource = aws_sns_topic.alarms.arn
      Condition = {
        ArnLike      = { "aws:SourceArn" = "arn:${local.partition}:cloudwatch:${local.region}:${local.account}:alarm:diskmon-*" }
        StringEquals = { "aws:SourceAccount" = local.account }
      }
    }]
  })
}

resource "aws_oam_link" "metrics" {
  count           = var.monitoring_sink_arn == null ? 0 : 1
  sink_identifier = var.monitoring_sink_arn
  label_template  = "$AccountName"
  resource_types  = ["AWS::CloudWatch::Metric"]
  link_configuration {
    metric_configuration { filter = "Namespace = '${local.namespace}'" }
  }
  lifecycle {
    precondition {
      condition     = try(split(":", var.monitoring_sink_arn)[3] == local.region && split(":", var.monitoring_sink_arn)[4] != local.account, false)
      error_message = "The OAM sink must be in the same Region and a different monitoring account."
    }
  }
}

resource "aws_cloudwatch_event_rule" "forward" {
  count = var.central_event_bus_arn == null ? 0 : 1
  name  = "${var.name}-forward"
  event_pattern = jsonencode({
    source        = ["aws.cloudwatch"]
    "detail-type" = ["CloudWatch Alarm State Change"]
    account       = [local.account]
    region        = [local.region]
    detail = {
      alarmName = [{ prefix = "diskmon-" }]
      state     = { value = ["ALARM", "OK", "INSUFFICIENT_DATA"] }
    }
  })
}

resource "aws_iam_role" "forward" {
  count = var.central_event_bus_arn == null ? 0 : 1
  name  = "${var.name}-forward"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRole", Principal = { Service = "events.amazonaws.com" }
      Condition = { ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.forward[0].arn }, StringEquals = { "aws:SourceAccount" = local.account } }
    }]
  })
}

resource "aws_iam_role_policy" "forward" {
  count = var.central_event_bus_arn == null ? 0 : 1
  role  = aws_iam_role.forward[0].id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "events:PutEvents", Resource = var.central_event_bus_arn }]
  })
}

resource "aws_cloudwatch_event_target" "forward" {
  count      = var.central_event_bus_arn == null ? 0 : 1
  rule       = aws_cloudwatch_event_rule.forward[0].name
  arn        = var.central_event_bus_arn
  role_arn   = aws_iam_role.forward[0].arn
  depends_on = [aws_iam_role_policy.forward]
  lifecycle {
    precondition {
      condition     = try(split(":", var.central_event_bus_arn)[3] == local.region, false)
      error_message = "This example requires a central bus in the same Region as the workload."
    }
  }
}