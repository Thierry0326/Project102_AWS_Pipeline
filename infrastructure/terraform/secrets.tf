# secrets.tf
# Stores pipeline configuration and API settings
# in AWS Secrets Manager
#
# Project 101 equivalent: .env file on local machine
# What AWS adds: IAM-controlled access, audit trail,
# automatic rotation, no file to accidentally commit

# ----------------------------------------------
# WORLD BANK API CONFIGURATION
# Stores the API base URL and settings
# Glue ingest job reads this at runtime
# ----------------------------------------------
resource "aws_secretsmanager_secret" "worldbank_config" {
  name        = "project102/worldbank/config"
  description = "World Bank API configuration for Project 102 ingest job"

  # How long AWS keeps a deleted secret before permanent removal
  # 0 = delete immediately (good for dev/learning)
  recovery_window_in_days = 0

  tags = {
    Name        = "project102-worldbank-config"
    Description = "World Bank API config for ingest job"
  }
}

resource "aws_secretsmanager_secret_version" "worldbank_config" {
  secret_id = aws_secretsmanager_secret.worldbank_config.id

  secret_string = jsonencode({
    api_base_url = "https://api.worldbank.org/v2"
    format       = "json"
    per_page     = "1000"
    indicators = [
      "NY.GDP.PCAP.CD",
      "SP.DYN.LE00.IN",
      "SH.XPD.CHEX.PC.CD",
      "SE.XPD.TOTL.GD.ZS",
      "SP.POP.TOTL",
      "SH.DYN.MORT",
      "SI.POV.DDAY",
      "SP.DYN.IMRT.IN"
    ]
    date_range_start = "1990"
    date_range_end   = "2024"
  })
}

# ----------------------------------------------
# PIPELINE CONFIGURATION
# Stores bucket names, region, and other
# pipeline settings Glue jobs need at runtime
# ----------------------------------------------
resource "aws_secretsmanager_secret" "pipeline_config" {
  name        = "project102/pipeline/config"
  description = "Pipeline configuration - bucket names and settings"

  recovery_window_in_days = 0

  tags = {
    Name        = "project102-pipeline-config"
    Description = "Pipeline config - buckets and settings"
  }
}

resource "aws_secretsmanager_secret_version" "pipeline_config" {
  secret_id = aws_secretsmanager_secret.pipeline_config.id

  secret_string = jsonencode({
    bronze_bucket = "${var.project_name}-bronze-raw"
    silver_bucket = "${var.project_name}-silver-processed"
    gold_bucket   = "${var.project_name}-gold-analytics"
    aws_region    = var.aws_region
    project_name  = var.project_name
    glue_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/project102-glue-role"
  })
}

# ----------------------------------------------
# DATA SOURCE - Gets current AWS account ID
# Used to build ARNs dynamically
# Avoids hardcoding your account ID anywhere
# ----------------------------------------------
data "aws_caller_identity" "current" {}