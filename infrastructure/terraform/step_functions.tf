# step_functions.tf
# Orchestrates the 3 Glue jobs + 5 crawlers into one automated pipeline
#
# Project 101 equivalent: the Airflow DAG (etl_pipeline.py) — same chain,
# same retry concept, but no scheduler container running 24/7
#
# What AWS adds: built-in retry/backoff per state, visual execution graph
# in the console, pay only per state transition (not per-second like a
# server), native Parallel state for running all 5 crawlers at once

# ----------------------------------------------
# IAM ROLE — what Step Functions is allowed to do
# Needs permission to start/monitor Glue jobs,
# start/check crawlers, and publish to SNS
# ----------------------------------------------
resource "aws_iam_role" "step_functions_role" {
  name = "${var.project_name}-step-functions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-step-functions-role"
    Description = "Allows Step Functions to run Glue jobs and crawlers and publish to SNS"
  }
}

resource "aws_iam_role_policy" "step_functions_glue" {
  name = "${var.project_name}-sfn-glue-access"
  role = aws_iam_role.step_functions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RunAndMonitorGlueJobs"
        Effect = "Allow"
        Action = [
          "glue:StartJobRun",
          "glue:GetJobRun",
          "glue:GetJobRuns",
          "glue:BatchStopJobRun"
        ]
        Resource = "*"
      },
      {
        Sid    = "RunAndCheckCrawlers"
        Effect = "Allow"
        Action = [
          "glue:StartCrawler",
          "glue:GetCrawler"
        ]
        Resource = "*"
      },
      {
        Sid    = "PublishNotifications"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.pipeline_success.arn,
          aws_sns_topic.pipeline_failure.arn
        ]
      },
      {
        # Required for the .sync Glue integration pattern —
        # Step Functions needs to react to Glue's own EventBridge events
        # to know when a job run actually finishes
        Sid    = "EventBridgeForSyncIntegration"
        Effect = "Allow"
        Action = [
          "events:PutTargets",
          "events:PutRule",
          "events:DescribeRule"
        ]
        Resource = [
          "arn:aws:events:${var.aws_region}:${data.aws_caller_identity.current.account_id}:rule/StepFunctionsGetEventForGlueJobRunRule"
        ]
      }
    ]
  })
}

# ----------------------------------------------
# STATE MACHINE
# Reads pipeline.asl.json and injects the SNS
# topic ARNs at deploy time via templatefile()
# ----------------------------------------------
resource "aws_sfn_state_machine" "pipeline" {
  name     = "${var.project_name}-pipeline"
  role_arn = aws_iam_role.step_functions_role.arn

  definition = templatefile("${path.module}/state_machine/pipeline.asl.json", {
    success_topic_arn = aws_sns_topic.pipeline_success.arn
    failure_topic_arn = aws_sns_topic.pipeline_failure.arn
  })

  tags = {
    Name        = "${var.project_name}-pipeline"
    Description = "Bronze to Silver to Gold to Crawl to Notify - replaces the P101 Airflow DAG"
  }
}
