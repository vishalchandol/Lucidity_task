variable "name" {
  type    = string
  default = "diskmon-central"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,39}$", var.name))
    error_message = "Use 3-40 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "source_account_ids" {
  type = set(string)
  validation {
    condition     = length(var.source_account_ids) > 0 && alltrue([for account in var.source_account_ids : can(regex("^[0-9]{12}$", account))])
    error_message = "Approve at least one explicit 12-digit source account ID; wildcards are forbidden."
  }
}