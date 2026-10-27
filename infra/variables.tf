variable "environment" {
  description = "Environment name: test or prod. Drives Multi-AZ, NAT redundancy, deletion protection and which secrets exist."
  type        = string
  validation {
    condition     = contains(["test", "prod"], var.environment)
    error_message = "environment must be test or prod."
  }
}

variable "region" {
  description = "Primary AWS region."
  type        = string
  default     = "ap-southeast-1"
}

variable "dr_region" {
  description = "Region that receives cross-region backup copies."
  type        = string
  default     = "ap-southeast-3"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "app_hostname" {
  description = "Public host name served by the ALB, e.g. hdb.example.com (DNS is managed outside this stack)."
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate for app_hostname in the primary region."
  type        = string
}

variable "frontend_instance_type" {
  type    = string
  default = "m6i.xlarge"
}

variable "frontend_count" {
  description = "OutSystems front-end servers, spread across the two AZs."
  type        = number
  default     = 2
  validation {
    condition     = var.frontend_count >= 1
    error_message = "At least one front-end is required."
  }
}

variable "db_instance_class" {
  type    = string
  default = "db.m6i.xlarge"
}

variable "db_allocated_storage_gb" {
  type    = number
  default = 200
}

variable "db_backup_retention_days" {
  description = "RDS automated backups (point-in-time restore window)."
  type        = number
  default     = 14
}

variable "backup_copy_retention_days" {
  description = "How long daily AWS Backup recovery points (primary and DR copy) are kept."
  type        = number
  default     = 35
}

variable "alert_emails" {
  description = "Addresses subscribed to the alerts topic (each must confirm the subscription)."
  type        = list(string)
  default     = []
}

variable "waf_rate_limit_per_5min" {
  description = "Requests per 5 minutes per client IP before WAF blocks (protects the anonymous search)."
  type        = number
  default     = 1000
}

variable "admin_allowed_cidrs" {
  description = "IPv4 CIDRs (corporate egress / VPN) allowed to reach the HDBResale_Admin module. Empty list = the admin app is unreachable from the internet."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for c in var.admin_allowed_cidrs : can(cidrhost(c, 0)) && !strcontains(c, ":")])
    error_message = "admin_allowed_cidrs must be IPv4 CIDRs, e.g. 203.0.113.0/24."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
