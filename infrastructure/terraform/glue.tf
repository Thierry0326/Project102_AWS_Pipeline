# glue.tf
# Defines the 3 Glue ETL jobs for the Medallion pipeline
#
# Project 101 equivalent: the 3 Python scripts in pipeline/
# What AWS adds: managed Spark cluster, auto-scaling, built-in CloudWatch logs,
#               no Docker, no scheduler process needed

locals {
  scripts_bucket = "${var.project_name}-glue-scripts"

  # Arguments shared by all three jobs
  common_args = {
    "--job-language"                     = "python"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--BRONZE_BUCKET"                    = "${var.project_name}-bronze-raw"
    "--SILVER_BUCKET"                    = "${var.project_name}-silver-processed"
    "--GOLD_BUCKET"                      = "${var.project_name}-gold-analytics"
    "--PIPELINE_SECRET_ARN"              = aws_secretsmanager_secret.pipeline_config.arn
    "--WORLDBANK_SECRET_ARN"             = aws_secretsmanager_secret.worldbank_config.arn
  }
}

# ----------------------------------------------
# BRONZE INGEST JOB
# World Bank API → S3 Bronze (raw JSONL)
# ----------------------------------------------
resource "aws_glue_job" "bronze_ingest" {
  name     = "${var.project_name}-bronze-ingest"
  role_arn = aws_iam_role.glue_role.arn

  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  max_retries       = 0
  timeout           = 60

  command {
    name            = "glueetl"
    script_location = "s3://${local.scripts_bucket}/jobs/job_bronze_ingest.py"
    python_version  = "3"
  }

  default_arguments = merge(local.common_args, {
    # requests is not pre-installed in Glue 4.0 PySpark — must declare it here
    "--additional-python-modules" = "requests"
  })

  tags = {
    Layer = "bronze"
  }
}

# ----------------------------------------------
# SILVER TRANSFORM JOB
# S3 Bronze (JSONL) → S3 Silver (Parquet)
# ----------------------------------------------
resource "aws_glue_job" "silver_transform" {
  name     = "${var.project_name}-silver-transform"
  role_arn = aws_iam_role.glue_role.arn

  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  max_retries       = 0
  timeout           = 60

  command {
    name            = "glueetl"
    script_location = "s3://${local.scripts_bucket}/jobs/job_silver_transform.py"
    python_version  = "3"
  }

  default_arguments = local.common_args

  tags = {
    Layer = "silver"
  }
}

# ----------------------------------------------
# GOLD MODEL JOB
# S3 Silver (Parquet) → S3 Gold (dimensional Parquet)
# Builds dim_country, dim_indicator, dim_year, fact_world_bank
# ----------------------------------------------
resource "aws_glue_job" "gold_model" {
  name     = "${var.project_name}-gold-model"
  role_arn = aws_iam_role.glue_role.arn

  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  max_retries       = 0
  timeout           = 60

  command {
    name            = "glueetl"
    script_location = "s3://${local.scripts_bucket}/jobs/job_gold_model.py"
    python_version  = "3"
  }

  default_arguments = local.common_args

  tags = {
    Layer = "gold"
  }
}
