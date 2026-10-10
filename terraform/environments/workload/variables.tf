variable "aws_profile" {
  type = string
  validation {
    condition     = can(regex("^[A-Za-z0-9_+=,.@-]+$", var.aws_profile))
    error_message = "Supply a nonempty named deployment profile."
  }
}
variable "aws_region" {
  type    = string
  default = "us-east-1"
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "Supply a commercial AWS Region such as us-east-1."
  }
}
variable "account_id" {
  type = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Supply the approved 12-digit workload account ID."
  }
}
variable "tooling_role_arn" { type = string }
variable "transfer_bucket_name" { type = string }
variable "session_instance_tags" {
  type    = map(string)
  default = { Monitoring = "enabled" }
}
variable "monitoring_sink_arn" {
  type    = string
  default = null
}
variable "central_event_bus_arn" {
  type    = string
  default = null
}