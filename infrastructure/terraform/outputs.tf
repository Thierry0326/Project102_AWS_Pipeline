# outputs.tf
# After terraform apply runs, these values
# get printed to the terminal
# Like print() statements at the end of your Python scripts

output "aws_region" {
  description = "Region where resources are deployed"
  value       = var.aws_region
}

output "project_name" {
  description = "Project name used across all resources"
  value       = var.project_name
}



output "vpc_id" {
  description = "VPC ID for Project 102"
  value       = aws_vpc.main.id
}

output "private_subnet_1_id" {
  description = "Private subnet 1 ID - used by Glue jobs"
  value       = aws_subnet.private_1.id
}

output "private_subnet_2_id" {
  description = "Private subnet 2 ID - used by Glue jobs"
  value       = aws_subnet.private_2.id
}

output "glue_security_group_id" {
  description = "Security group ID for Glue jobs"
  value       = aws_security_group.glue.id
}



output "worldbank_secret_arn" {
  description = "ARN of World Bank config secret"
  value       = aws_secretsmanager_secret.worldbank_config.arn
}

output "pipeline_config_secret_arn" {
  description = "ARN of pipeline config secret"
  value       = aws_secretsmanager_secret.pipeline_config.arn
}

output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}