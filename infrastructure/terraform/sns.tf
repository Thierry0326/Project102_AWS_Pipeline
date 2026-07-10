# sns.tf
# SNS topics for pipeline notifications
#
# Project 101 equivalent: the notify_success Airflow task (just logged to console)
# What AWS adds: real email delivery, can fan out to SMS/Lambda/Slack later,
#               decoupled from the pipeline itself (Step Functions just publishes
#               a message, SNS handles delivery + retries)

# ----------------------------------------------
# SUCCESS TOPIC
# Step Functions publishes here when all 3 Glue
# jobs + crawlers finish without error
# ----------------------------------------------
resource "aws_sns_topic" "pipeline_success" {
  name = "${var.project_name}-pipeline-success"

  tags = {
    Name        = "${var.project_name}-pipeline-success"
    Description = "Notified when the full Bronze-to-Silver-to-Gold pipeline completes"
  }
}

resource "aws_sns_topic_subscription" "success_email" {
  topic_arn = aws_sns_topic.pipeline_success.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ----------------------------------------------
# FAILURE TOPIC
# Step Functions publishes here if ANY state
# (any Glue job or any crawler) fails
# ----------------------------------------------
resource "aws_sns_topic" "pipeline_failure" {
  name = "${var.project_name}-pipeline-failure"

  tags = {
    Name        = "${var.project_name}-pipeline-failure"
    Description = "Notified immediately if any pipeline state fails"
  }
}

resource "aws_sns_topic_subscription" "failure_email" {
  topic_arn = aws_sns_topic.pipeline_failure.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
