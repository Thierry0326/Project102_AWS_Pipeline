# main.tf
# This tells Terraform we are building on AWS
# and which region to build in

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  required_version = ">= 1.5.0"
}

provider "aws" {
  region = var.aws_region

  # These tags get applied to every resource
  # automatically — good habit from day one
  default_tags {
    tags = {
      Project     = "project102"
      Environment = "dev"
      Owner       = "Thierry"
      ManagedBy   = "Terraform"
    }
  }
}