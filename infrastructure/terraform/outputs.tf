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



output "glue_role_arn" {
  description = "IAM role ARN used by all Glue jobs"
  value       = aws_iam_role.glue_role.arn
}

output "glue_job_bronze_name" {
  description = "Glue job name for bronze ingest (World Bank API → S3)"
  value       = aws_glue_job.bronze_ingest.name
}

output "glue_job_silver_name" {
  description = "Glue job name for silver transform (JSON → Parquet)"
  value       = aws_glue_job.silver_transform.name
}

output "glue_job_gold_name" {
  description = "Glue job name for gold model (dim/fact build)"
  value       = aws_glue_job.gold_model.name
}

output "glue_scripts_bucket" {
  description = "S3 bucket that holds Glue job scripts"
  value       = aws_s3_bucket.glue_scripts.id
}



output "glue_catalog_database" {
  description = "Glue Data Catalog database name — use this in Athena"
  value       = aws_glue_catalog_database.project102.name
}

output "athena_query_hint" {
  description = "Reminder: set this as your Athena query result location before querying"
  value       = "s3://${var.project_name}-silver-processed/athena-results/"
}



output "state_machine_arn" {
  description = "ARN of the Step Functions pipeline - used to start executions and as the EventBridge target in Phase 4"
  value       = aws_sfn_state_machine.pipeline.arn
}

output "state_machine_name" {
  description = "Name of the Step Functions pipeline"
  value       = aws_sfn_state_machine.pipeline.name
}

output "sns_success_topic_arn" {
  description = "ARN of the SNS topic notified when the pipeline completes successfully"
  value       = aws_sns_topic.pipeline_success.arn
}

output "sns_failure_topic_arn" {
  description = "ARN of the SNS topic notified when any pipeline state fails"
  value       = aws_sns_topic.pipeline_failure.arn
}