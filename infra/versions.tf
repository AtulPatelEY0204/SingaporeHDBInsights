terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.6"
    }
  }

  # Partial configuration: supply bucket/key/region/dynamodb_table with
  # `terraform init -backend-config=envs/<env>.backend.hcl`.
  backend "s3" {}
}

provider "aws" {
  region = var.region
  default_tags {
    tags = local.tags
  }
}

# Disaster-recovery region for cross-region backup copies.
provider "aws" {
  alias  = "dr"
  region = var.dr_region
  default_tags {
    tags = local.tags
  }
}
