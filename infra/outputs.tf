output "alb_dns_name" {
  description = "Point app_hostname (CNAME/alias) at this."
  value       = aws_lb.this.dns_name
}

output "health_url" {
  value = local.health_url
}

output "frontend_instance_ids" {
  value = aws_instance.frontend[*].id
}

output "deployment_controller_instance_id" {
  value = aws_instance.deployment_controller.id
}

output "db_endpoint" {
  description = "Use in OutSystems Configuration Tool."
  value       = aws_db_instance.this.address
}

output "db_master_secret_arn" {
  value = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "datagov_api_key_secret_arn" {
  value = aws_secretsmanager_secret.datagov_api_key.arn
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}
