# sns.tf
# SNS topics for pipeline notifications
#
# Project 101 equivalent: the notify_success Airflow task (just logged to console)
# What AWS adds: real email delivery, can fan out to SMS/Lambda/Slack later,
#               decoupled from the pipeline itself (Step Functions just publishes
#               a message, SNS handles delivery + retries)
#
# kms_master_key_id uses the AWS-managed key (free, unlike a customer-managed
# CMK which runs ~$1/mo) - flagged by Trivy (AWS-0095) as unencrypted
# otherwise. Publishing to an encrypted topic needs kms:GenerateDataKey +
# kms:Decrypt in addition to sns:Publish - see step_functions.tf.
#
# No data "aws_kms_alias" lookup here on purpose: alias/aws/sns is created
# lazily by AWS the first time an account actually encrypts an SNS topic
# with it, so a data source can't find it before that first apply - it's
# referenced directly by its predictable ARN pattern instead (region +
# account + fixed name), which needs no lookup and becomes valid the
# moment these topics are created.

# ----------------------------------------------
# SUCCESS TOPIC
# Step Functions publishes here when all 3 Glue
# jobs + crawlers finish without error
# ----------------------------------------------
# AWS-0136 wants a customer-managed KMS key instead of the AWS-managed one
# for finer rotation/access control. Skipped deliberately: ~$1/mo for a
# topic that just emails one address has no real security payoff here.
# trivy:ignore:AWS-0136
resource "aws_sns_topic" "pipeline_success" {
  name              = "${var.project_name}-pipeline-success"
  kms_master_key_id = "alias/aws/sns"

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
# Same tradeoff as pipeline_success above - see that comment.
# trivy:ignore:AWS-0136
resource "aws_sns_topic" "pipeline_failure" {
  name              = "${var.project_name}-pipeline-failure"
  kms_master_key_id = "alias/aws/sns"

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
