# eventbridge.tf
# NOTE: NOT applied — kept for documentation/future use
# Uncomment and terraform apply when daily scheduling is needed
# Cost impact: each triggered run = ~$0.15 in Glue DPU charges
#
# Project 101 equivalent: Airflow's schedule_interval
# What AWS adds: no scheduler process running 24/7 - EventBridge just
# fires an event on a timer and Step Functions takes it from there

# resource "aws_iam_role" "eventbridge_role" {
#   name = "${var.project_name}-eventbridge-role"
#
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Principal = {
#           Service = "events.amazonaws.com"
#         }
#         Action = "sts:AssumeRole"
#       }
#     ]
#   })
# }
#
# # Least-privilege: only allowed to start THIS state machine, nothing else
# resource "aws_iam_role_policy" "eventbridge_start_execution" {
#   name = "${var.project_name}-eventbridge-sfn-start"
#   role = aws_iam_role.eventbridge_role.id
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect   = "Allow"
#         Action   = "states:StartExecution"
#         Resource = aws_sfn_state_machine.pipeline.arn
#       }
#     ]
#   })
# }
#
# resource "aws_cloudwatch_event_rule" "daily_pipeline" {
#   name                = "project102-daily-pipeline"
#   schedule_expression = "cron(0 6 * * ? *)"  # 06:00 UTC daily
# }
#
# resource "aws_cloudwatch_event_target" "trigger_pipeline" {
#   rule     = aws_cloudwatch_event_rule.daily_pipeline.name
#   arn      = aws_sfn_state_machine.pipeline.arn
#   role_arn = aws_iam_role.eventbridge_role.arn
#
#   # Without this, EventBridge passes the raw event JSON (source,
#   # detail-type, etc.) as the state machine's input instead of the
#   # empty {} the pipeline expects - all params are hardcoded via
#   # templatefile() in step_functions.tf, so no input is needed.
#   input = "{}"
# }
