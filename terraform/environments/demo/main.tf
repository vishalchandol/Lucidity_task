locals { name = "diskmon-demo-${var.aws_region}" }

module "workload" {
  source                = "../../modules/workload"
  name                  = local.name
  tooling_role_arn      = var.tooling_role_arn
  transfer_bucket_name  = var.transfer_bucket_name
  session_instance_tags = { Purpose = "DiskMonitoringDemo" }
}
module "dashboard" {
  source      = "../../modules/dashboard"
  name        = local.name
  account_ids = [var.account_id]
  region      = var.aws_region
}

data "aws_ami" "al2023" {
  count       = var.create_demo_instance ? 1 : 0
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_iam_role" "instance" {
  count = var.create_demo_instance ? 1 : 0
  name  = "${local.name}-instance"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "metrics" {
  count      = var.create_demo_instance ? 1 : 0
  role       = aws_iam_role.instance[0].name
  policy_arn = module.workload.instance_metric_policy_arn
}

resource "aws_iam_role_policy_attachment" "ssm_bootstrap" {
  count      = var.create_demo_instance ? 1 : 0
  role       = aws_iam_role.instance[0].name
  policy_arn = module.workload.ssm_bootstrap_policy_arn
}

resource "aws_iam_instance_profile" "demo" {
  count = var.create_demo_instance ? 1 : 0
  name  = "${local.name}-instance"
  role  = aws_iam_role.instance[0].name
}

resource "aws_instance" "demo" {
  count                       = var.create_demo_instance ? 1 : 0
  ami                         = data.aws_ami.al2023[0].id
  instance_type               = "t3.micro"
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = var.security_group_ids
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.demo[0].name
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  root_block_device {
    encrypted             = true
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
  }
  tags       = { Name = "diskmon-demo", Purpose = "DiskMonitoringDemo" }
  depends_on = [aws_iam_role_policy_attachment.metrics, aws_iam_role_policy_attachment.ssm_bootstrap]
}
