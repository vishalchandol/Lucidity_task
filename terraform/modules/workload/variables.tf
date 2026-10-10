variable "name" {
  type    = string
  default = "diskmon"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,39}$", var.name))
    error_message = "Use 3-40 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "tooling_role_arn" {
  type = string
  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.tooling_role_arn))
    error_message = "Supply an explicit tooling IAM role ARN, not an account root or wildcard."
  }
}

variable "transfer_bucket_name" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.transfer_bucket_name))
    error_message = "Use a globally unique 3-63 character lowercase bucket name with hyphens only."
  }
}

variable "session_instance_tags" {
  type    = map(string)
  default = {}
  validation {
    condition     = alltrue([for key, value in var.session_instance_tags : length(key) > 0 && length(value) > 0 && !startswith(lower(key), "aws:")])
    error_message = "Session tag boundary keys and values must be nonempty; reserved aws: tags are not supported."
  }
}

variable "monitoring_sink_arn" {
  type    = string
  default = null
  validation {
    condition     = var.monitoring_sink_arn == null ? true : can(regex("^arn:aws:oam:[a-z0-9-]+:[0-9]{12}:sink/[a-f0-9-]+$", var.monitoring_sink_arn))
    error_message = "Supply a regional OAM sink ARN or null."
  }
}

variable "central_event_bus_arn" {
  type    = string
  default = null
  validation {
    condition     = var.central_event_bus_arn == null ? true : can(regex("^arn:aws:events:[a-z0-9-]+:[0-9]{12}:event-bus/[A-Za-z0-9._-]+$", var.central_event_bus_arn))
    error_message = "Supply a central EventBridge bus ARN or null."
  }
}