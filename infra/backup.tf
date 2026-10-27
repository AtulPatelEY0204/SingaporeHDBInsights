# Daily recovery points with a copy in the DR region (region-loss RPO <= 24 h).
# RDS automated backups in database.tf provide the 5-minute point-in-time window.

resource "aws_kms_key" "dr_backup" {
  provider                = aws.dr
  description             = "${local.name} DR backup vault"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_backup_vault" "primary" {
  name        = "${local.name}-primary"
  kms_key_arn = aws_kms_key.data.arn
}

resource "aws_backup_vault" "dr" {
  provider    = aws.dr
  name        = "${local.name}-dr"
  kms_key_arn = aws_kms_key.dr_backup.arn
}

resource "aws_backup_plan" "this" {
  name = local.name
  rule {
    rule_name         = "daily-with-dr-copy"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = "cron(0 17 * * ? *)" # 01:00 SGT, before the 02:00 sync
    start_window      = 60
    completion_window = 240
    lifecycle {
      delete_after = var.backup_copy_retention_days
    }
    copy_action {
      destination_vault_arn = aws_backup_vault.dr.arn
      lifecycle {
        delete_after = var.backup_copy_retention_days
      }
    }
  }
}

resource "aws_iam_role" "backup" {
  name = "${local.name}-backup"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "backup.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

resource "aws_backup_selection" "rds" {
  name         = "${local.name}-rds"
  plan_id      = aws_backup_plan.this.id
  iam_role_arn = aws_iam_role.backup.arn
  resources    = [aws_db_instance.this.arn]
}
