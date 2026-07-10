resource "aws_iam_role" "glue_role" {
  name = "${var.project_name}-glue-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "glue.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Project = var.project_name
  }
}

# AWS managed policy — gives Glue basic service permissions
resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# S3 access — read/write on all three medallion buckets + scripts bucket
resource "aws_iam_role_policy" "glue_s3" {
  name = "${var.project_name}-glue-s3"
  role = aws_iam_role.glue_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "MedallionBuckets"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::project102-bronze-raw",
          "arn:aws:s3:::project102-bronze-raw/*",
          "arn:aws:s3:::project102-silver-processed",
          "arn:aws:s3:::project102-silver-processed/*",
          "arn:aws:s3:::project102-gold-analytics",
          "arn:aws:s3:::project102-gold-analytics/*",
          "arn:aws:s3:::project102-glue-scripts",
          "arn:aws:s3:::project102-glue-scripts/*"
        ]
      }
    ]
  })
}

# Secrets Manager — read-only on project102 secrets
resource "aws_iam_role_policy" "glue_secrets" {
  name = "${var.project_name}-glue-secrets"
  role = aws_iam_role.glue_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadPipelineSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:us-east-1:451523008307:secret:project102/*"
        ]
      }
    ]
  })
}

# CloudWatch Logs — Glue writes job logs here
resource "aws_iam_role_policy" "glue_logs" {
  name = "${var.project_name}-glue-logs"
  role = aws_iam_role.glue_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:us-east-1:451523008307:log-group:/aws-glue/*"
      }
    ]
  })
}
