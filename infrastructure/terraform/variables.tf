# variables.tf
# Reusable variables so we never hardcode values
# Think of this as your .env file for Terraform

variable "aws_region" {
  description = "AWS region for all Project 102 resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project identifier used in resource names"
  type        = string
  default     = "project102"
}

variable "environment" {
  description = "Environment tag"
  type        = string
  default     = "dev"
}