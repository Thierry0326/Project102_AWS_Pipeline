# glue_crawler.tf
# Glue Crawlers scan S3 and register tables in the Glue Data Catalog
#
# Project 101 equivalent: mysql_schema.sql (you defined the schema manually)
# What AWS adds: schema is auto-inferred from the Parquet files — no DDL needed.
# Athena reads the catalog to know column names, types, and partition layout.

# ----------------------------------------------
# GLUE DATABASE
# A namespace that groups related tables.
# Think of it like a MySQL database/schema.
# ----------------------------------------------
resource "aws_glue_catalog_database" "project102" {
  name        = "project102"
  description = "Glue Data Catalog for Project 102 - Bronze, Silver, Gold layers"
}

# ----------------------------------------------
# SILVER CRAWLER
# Registers the cleaned Parquet as a table
# partitioned by year — useful for debugging
# and validation queries in Athena
# ----------------------------------------------
resource "aws_glue_crawler" "silver" {
  name          = "${var.project_name}-silver-crawler"
  role          = aws_iam_role.glue_role.arn
  database_name = aws_glue_catalog_database.project102.name

  s3_target {
    path = "s3://${var.project_name}-silver-processed/worldbank/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Tables     = { AddOrUpdateBehavior = "MergeNewColumns" }
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
  })

  tags = {
    Layer = "silver"
  }
}

# ----------------------------------------------
# GOLD CRAWLERS — one per table
# Separate crawlers keep each dim/fact table
# clean in the catalog. A single crawler on the
# gold/ prefix would merge all 4 into one table.
# ----------------------------------------------
resource "aws_glue_crawler" "gold_dim_country" {
  name          = "${var.project_name}-gold-dim-country"
  role          = aws_iam_role.glue_role.arn
  database_name = aws_glue_catalog_database.project102.name

  s3_target {
    path = "s3://${var.project_name}-gold-analytics/dim_country/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  tags = {
    Layer = "gold"
  }
}

resource "aws_glue_crawler" "gold_dim_indicator" {
  name          = "${var.project_name}-gold-dim-indicator"
  role          = aws_iam_role.glue_role.arn
  database_name = aws_glue_catalog_database.project102.name

  s3_target {
    path = "s3://${var.project_name}-gold-analytics/dim_indicator/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  tags = {
    Layer = "gold"
  }
}

resource "aws_glue_crawler" "gold_dim_year" {
  name          = "${var.project_name}-gold-dim-year"
  role          = aws_iam_role.glue_role.arn
  database_name = aws_glue_catalog_database.project102.name

  s3_target {
    path = "s3://${var.project_name}-gold-analytics/dim_year/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  tags = {
    Layer = "gold"
  }
}

resource "aws_glue_crawler" "gold_fact_world_bank" {
  name          = "${var.project_name}-gold-fact-world-bank"
  role          = aws_iam_role.glue_role.arn
  database_name = aws_glue_catalog_database.project102.name

  s3_target {
    path = "s3://${var.project_name}-gold-analytics/fact_world_bank/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  tags = {
    Layer = "gold"
  }
}
