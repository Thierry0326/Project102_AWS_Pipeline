# s3.tf
# Creates the three S3 buckets for the Medallion Architecture
# Bronze = raw data, Silver = cleaned, Gold = analytical
#
# Project 101 equivalent:
# Bronze = SQL Server, Silver = MySQL processed, Gold = MySQL analytics

# ----------------------------------------------
# BRONZE BUCKET — Raw World Bank API JSON
# ----------------------------------------------
resource "aws_s3_bucket" "bronze" {
  bucket = "${var.project_name}-bronze-raw"

  tags = {
    Layer       = "bronze"
    Description = "Raw JSON from World Bank API - untouched"
  }
}

# Block all public access — data is private
resource "aws_s3_bucket_public_access_block" "bronze" {
  bucket = aws_s3_bucket.bronze.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning — keeps history of every file
resource "aws_s3_bucket_versioning" "bronze" {
  bucket = aws_s3_bucket.bronze.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Makes explicit what AWS already applies by default (SSE-S3 on every
# bucket since 2023) rather than leaving it implicit/unaudited. AWS-0132
# wants a customer-managed KMS key instead - skipped deliberately, same
# reasoning as s3_glue_scripts_append.tf: no sensitive data, no compliance
# need for custom key rotation, ~$1/mo per key for no real payoff here.
# trivy:ignore:AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "bronze" {
  bucket = aws_s3_bucket.bronze.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle rule — move Bronze to Glacier after 30 days
# Bronze is raw/untouched data we rarely query
# Glacier = ~$0.004/GB vs S3 standard ~$0.023/GB
resource "aws_s3_bucket_lifecycle_configuration" "bronze" {
  bucket = aws_s3_bucket.bronze.id

  rule {
    id     = "move-to-glacier"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "GLACIER_IR" # Glacier Instant Retrieval
    }
  }
}

# ----------------------------------------------
# SILVER BUCKET — Cleaned Parquet Files
# ----------------------------------------------
resource "aws_s3_bucket" "silver" {
  bucket = "${var.project_name}-silver-processed"

  tags = {
    Layer       = "silver"
    Description = "Cleaned and normalized Parquet files"
  }
}

resource "aws_s3_bucket_public_access_block" "silver" {
  bucket = aws_s3_bucket.silver.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "silver" {
  bucket = aws_s3_bucket.silver.id

  versioning_configuration {
    status = "Enabled"
  }
}

# See bronze's identical block above for the AWS-0132 suppression reasoning.
# trivy:ignore:AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "silver" {
  bucket = aws_s3_bucket.silver.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ----------------------------------------------
# GOLD BUCKET - Dimensional Parquet (Analytics)
# ----------------------------------------------
resource "aws_s3_bucket" "gold" {
  bucket = "${var.project_name}-gold-analytics"

  tags = {
    Layer       = "gold"
    Description = "Dimensional model: dim_country dim_indicator dim_year fact_world_bank"
  }
}

resource "aws_s3_bucket_public_access_block" "gold" {
  bucket = aws_s3_bucket.gold.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "gold" {
  bucket = aws_s3_bucket.gold.id

  versioning_configuration {
    status = "Enabled"
  }
}

# See bronze's identical block near the top of this file for the AWS-0132
# suppression reasoning.
# trivy:ignore:AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "gold" {
  bucket = aws_s3_bucket.gold.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}