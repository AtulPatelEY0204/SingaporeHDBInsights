# OutSystems 11 Platform Server is installed and registered with LifeTime by the
# platform runbook (installer + Configuration Tool); Terraform provides hardened,
# SSM-managed Windows hosts. No SSH/RDP keys: access is SSM Session Manager only.

data "aws_ami" "windows" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }
}

locals {
  # Timer schedules in OutSystems run on server time; the nightly sync is 02:00 SGT.
  windows_user_data = <<-EOT
    <powershell>
    Set-TimeZone -Id "Singapore Standard Time"
    </powershell>
  EOT
}

resource "aws_instance" "frontend" {
  count                  = var.frontend_count
  ami                    = data.aws_ami.windows.id
  instance_type          = var.frontend_instance_type
  subnet_id              = aws_subnet.app[count.index % 2].id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name
  user_data              = local.windows_user_data
  monitoring             = true

  metadata_options {
    http_tokens   = "required" # IMDSv2 only
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 100
    encrypted   = true
    kms_key_id  = aws_kms_key.data.arn
  }

  tags = { Name = "${local.name}-fe-${count.index + 1}", Role = "outsystems-frontend" }

  lifecycle {
    ignore_changes = [ami] # AMI refreshes are rolled out deliberately, not on every plan
  }
}

resource "aws_instance" "deployment_controller" {
  ami                    = data.aws_ami.windows.id
  instance_type          = var.frontend_instance_type
  subnet_id              = aws_subnet.app[0].id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name
  user_data              = local.windows_user_data
  monitoring             = true

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 100
    encrypted   = true
    kms_key_id  = aws_kms_key.data.arn
  }

  tags = { Name = "${local.name}-controller", Role = "outsystems-deployment-controller" }

  lifecycle {
    ignore_changes = [ami]
  }
}
