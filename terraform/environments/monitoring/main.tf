module "monitoring" {
  source             = "../../modules/monitoring"
  name               = "diskmon-central-${var.aws_region}"
  source_account_ids = var.source_account_ids
}
