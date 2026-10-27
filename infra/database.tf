resource "aws_db_subnet_group" "this" {
  name       = local.name
  subnet_ids = aws_subnet.db[*].id
}

resource "aws_db_instance" "this" {
  identifier     = local.name
  engine         = "sqlserver-se"
  license_model  = "license-included"
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage_gb
  max_allocated_storage = var.db_allocated_storage_gb * 2
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.data.arn

  # Prod: synchronous standby in the second AZ (RPO 0, failover <= 5 min).
  multi_az               = local.is_prod
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  # Master credentials live in an RDS-managed Secrets Manager secret (rotated by AWS).
  username                      = "osadmin"
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.data.arn

  # Point-in-time restore window (RPO <= 5 min for app data). Windows avoid the 02:00 SGT sync.
  backup_retention_period = var.db_backup_retention_days
  backup_window           = "16:00-17:00" # 00:00-01:00 SGT
  maintenance_window      = "Sun:20:00-Sun:21:00"
  copy_tags_to_snapshot   = true

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.data.arn
  performance_insights_retention_period = 7
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.rds_monitoring.arn
  enabled_cloudwatch_logs_exports       = ["error", "agent"]

  auto_minor_version_upgrade = true
  deletion_protection        = local.is_prod
  skip_final_snapshot        = !local.is_prod
  final_snapshot_identifier  = local.is_prod ? "${local.name}-final" : null
}

resource "aws_iam_role" "rds_monitoring" {
  name = "${local.name}-rds-monitoring"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "monitoring.rds.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ---------- Application secrets (values are set out of band, never in Terraform state) ----------
resource "aws_secretsmanager_secret" "datagov_api_key" {
  name        = "${local.name}/datagov-api-key"
  description = "data.gov.sg API key -> HDBResale_Core Site.DataGovSG_ApiKey"
  kms_key_id  = aws_kms_key.data.arn
}

resource "aws_secretsmanager_secret" "test_api_token" {
  count       = local.is_prod ? 0 : 1 # the test runner never exists in Prod
  name        = "${local.name}/test-api-token"
  description = "HDBResale_Tests Site.TestApiToken (also the TEST_API_TOKEN GitHub secret)"
  kms_key_id  = aws_kms_key.data.arn
}
