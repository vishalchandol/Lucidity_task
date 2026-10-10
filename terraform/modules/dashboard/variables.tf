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