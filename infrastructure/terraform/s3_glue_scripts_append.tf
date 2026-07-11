# ── Glue scripts bucket ──────────────────────────────────────────────────────
# Append this block to your existing s3.tf

resource "aws_s3_bucket" "glue_scripts" {
  bucket = "${var.project_name}-glue-scripts"

  tags = {
    Project = var.project_name
    Layer   = "scripts"
  }
}

resource "aws_s3_bucket_versioning" "glue_scripts" {
  bucket = aws_s3_bucket.glue_scripts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# AWS-0132 wants SSE-KMS with a customer-managed key instead of SSE-S3
# (AES256, AWS-managed, free). Skipped deliberately, same reasoning as the
# SNS topics in sns.tf: this bucket only holds 3 Python scripts, no
# sensitive data or compliance need for custom key rotation - ~$1/mo for
# no real security payoff here.
# trivy:ignore:AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "glue_scripts" {
  bucket = aws_s3_bucket.glue_scripts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "glue_scripts" {
  bucket                  = aws_s3_bucket.glue_scripts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── Upload the Glue job scripts ──────────────────────────────────────────────
# glue.tf's script_location args point here. Without these resources the
# bucket exists but is empty, so every Glue job run fails with
# "script file does not exist". etag = filemd5() re-uploads on any edit.
resource "aws_s3_object" "job_bronze_ingest" {
  bucket = aws_s3_bucket.glue_scripts.id
  key    = "jobs/job_bronze_ingest.py"
  source = "${path.module}/../../glue_jobs/job_bronze_ingest.py"
  etag   = filemd5("${path.module}/../../glue_jobs/job_bronze_ingest.py")
}

resource "aws_s3_object" "job_silver_transform" {
  bucket = aws_s3_bucket.glue_scripts.id
  key    = "jobs/job_silver_transform.py"
  source = "${path.module}/../../glue_jobs/job_silver_transform.py"
  etag   = filemd5("${path.module}/../../glue_jobs/job_silver_transform.py")
}

resource "aws_s3_object" "job_gold_model" {
  bucket = aws_s3_bucket.glue_scripts.id
  key    = "jobs/job_gold_model.py"
  source = "${path.module}/../../glue_jobs/job_gold_model.py"
  etag   = filemd5("${path.module}/../../glue_jobs/job_gold_model.py")
}
