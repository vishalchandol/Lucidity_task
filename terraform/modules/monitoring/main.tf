terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_oam_sink" "metrics" { name = var.name }

resource "aws_oam_sink_policy" "metrics" {
  sink_identifier = aws_oam_sink.metrics.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = ["oam:CreateLink", "oam:UpdateLink"]
      Principal = { AWS = var.source_account_ids }
      Resource  = aws_oam_sink.metrics.arn
      Condition = {
        "ForAllValues:StringEquals" = { "oam:ResourceTypes" = ["AWS::CloudWatch::Metric"] }
        Null                        = { "oam:ResourceTypes" = "false" }
      }
    }]
  })
}

resource "aws_sns_topic" "alerts" { name = "${var.name}-alerts" }
resource "aws_cloudwatch_event_bus" "alerts" { name = "${var.name}-alerts" }

resource "aws_cloudwatch_event_bus_policy" "sources" {
  event_bus_name = aws_cloudwatch_event_bus.alerts.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "ApprovedCloudWatchForwarders", Effect = "Allow", Action = "events:PutEvents"
      Principal = { AWS = var.source_account_ids }
      Resource  = aws_cloudwatch_event_bus.alerts.arn
      Condition = {
        StringEquals = { "events:source" = "aws.cloudwatch", "events:detail-type" = "CloudWatch Alarm State Change" }
        Bool         = { "events:eventBusInvocation" = "true" }
      }
    }]
  })
}

resource "aws_cloudwatch_event_rule" "alerts" {
  name           = "${var.name}-alerts"
  event_bus_name = aws_cloudwatch_event_bus.alerts.name
  event_pattern = jsonencode({
    source        = ["aws.cloudwatch"]
    "detail-type" = ["CloudWatch Alarm State Change"]
    account       = var.source_account_ids
    region        = [data.aws_region.current.region]
    detail = {
      alarmName = [{ prefix = "diskmon-" }]
      state     = { value = ["ALARM", "OK", "INSUFFICIENT_DATA"] }
    }
  })
}

resource "aws_iam_role" "alerts" {
  name = "${var.name}-sns-publish"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnEquals    = { "aws:SourceArn" = aws_cloudwatch_event_rule.alerts.arn }
      }
    }]
  })
}

resource "aws_iam_role_policy" "alerts" {
  name = "${var.name}-sns-publish"
  role = aws_iam_role.alerts.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = aws_sns_topic.alerts.arn
    }]
  })
}

resource "aws_cloudwatch_event_target" "alerts" {
  rule           = aws_cloudwatch_event_rule.alerts.name
  event_bus_name = aws_cloudwatch_event_bus.alerts.name
  arn            = aws_sns_topic.alerts.arn
  role_arn       = aws_iam_role.alerts.arn
  depends_on     = [aws_iam_role_policy.alerts]
}

module "dashboard" {
  source      = "../dashboard"
  name        = var.name
  account_ids = var.source_account_ids
  region      = data.aws_region.current.region
}