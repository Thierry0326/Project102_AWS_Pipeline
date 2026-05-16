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
