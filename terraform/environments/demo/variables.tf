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
    error_message = "Supply the approved 12-digit demo account ID."
  }
}
variable "tooling_role_arn" {
  type = string
  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.tooling_role_arn))
    error_message = "Supply an explicit existing tooling role ARN."
  }
  validation {
    condition     = try(split(":", var.tooling_role_arn)[4] == var.account_id, false)
    error_message = "The standalone demo tooling role must belong to the declared demo account."
  }
}
variable "transfer_bucket_name" { type = string }
variable "create_demo_instance" {
  type    = bool
  default = false
}
variable "subnet_id" {
  type    = string
  default = null
  validation {
    condition     = var.create_demo_instance ? can(regex("^subnet-[a-f0-9]{8,17}$", var.subnet_id)) : var.subnet_id == null || can(regex("^subnet-[a-f0-9]{8,17}$", var.subnet_id))
    error_message = "An existing subnet ID is required when create_demo_instance is true."
  }
}
variable "security_group_ids" {
  type    = list(string)
  default = []
  validation {
    condition     = (!var.create_demo_instance || length(var.security_group_ids) > 0) && alltrue([for group in var.security_group_ids : can(regex("^sg-[a-f0-9]{8,17}$", group))])
    error_message = "Supply existing security group IDs, at least one when creating the demo instance."
  }
}