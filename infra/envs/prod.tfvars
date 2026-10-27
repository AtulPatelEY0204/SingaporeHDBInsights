environment            = "prod"
app_hostname           = "hdb.example.com"
certificate_arn        = "arn:aws:acm:ap-southeast-1:111111111111:certificate/REPLACE-ME"
frontend_count         = 2
frontend_instance_type = "m6i.xlarge"
db_instance_class      = "db.m6i.xlarge"
alert_emails           = ["ops@example.com"]
admin_allowed_cidrs    = ["203.0.113.0/24"] # REPLACE-ME: corporate egress / VPN ranges
