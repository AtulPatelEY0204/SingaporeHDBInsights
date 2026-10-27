locals {
  name    = "hdb-resale-${var.environment}"
  is_prod = var.environment == "prod"
  azs     = slice(data.aws_availability_zones.available.names, 0, 2)
  tags = merge({
    Application = "HDB Resale Explorer"
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)
  health_url = "https://${var.app_hostname}/HDBResale_Core/rest/HealthAPI/Health"
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_elb_service_account" "this" {}

# One customer-managed key for data at rest (RDS, EBS, secrets, backups, logs, SNS).
resource "aws_kms_key" "data" {
  description             = "${local.name} data at rest"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "data" {
  name          = "alias/${local.name}-data"
  target_key_id = aws_kms_key.data.key_id
}

data "aws_iam_policy_document" "kms" {
  statement {
    sid       = "AccountAdmin"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
  statement {
    sid       = "AwsServicesUse"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey", "kms:CreateGrant"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com", "sns.amazonaws.com", "cloudwatch.amazonaws.com"]
    }
  }
}
