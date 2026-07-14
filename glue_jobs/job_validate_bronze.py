"""
job_validate_bronze.py
Data quality gate for S3 Bronze (raw World Bank JSON)

Project 101 equivalent: the validate_pipeline task in the Airflow DAG,
but per-layer instead of once at the end
What AWS adds: nothing here - this is the same Great Expectations library
               Project 101 used (pinned to 0.18.22, same reason: 1.x is a
               breaking API rewrite), just running inside a Glue job
               against a Spark dataframe instead of pandas

Catches: a totally empty/failed API response, or World Bank changing the
shape of their JSON response (which would silently break Silver's
column selection otherwise)
"""
import sys

import great_expectations as gx
from great_expectations.core.batch import RuntimeBatchRequest

from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext

args = getResolvedOptions(sys.argv, [
    "JOB_NAME",
    "BRONZE_BUCKET",
])

sc = SparkContext()
glue_context = GlueContext(sc)
spark = glue_context.spark_session
logger = glue_context.get_logger()

BRONZE_BUCKET = args["BRONZE_BUCKET"]
bronze_path = f"s3://{BRONZE_BUCKET}/worldbank/raw/"

logger.info(f"Reading bronze from {bronze_path}")
df = spark.read.option("recursiveFileLookup", "true").json(bronze_path)

context = gx.get_context()
context.add_datasource(
    **{
        "name": "spark_datasource",
        "class_name": "Datasource",
        "execution_engine": {"class_name": "SparkDFExecutionEngine"},
        "data_connectors": {
            "runtime_connector": {
                "class_name": "RuntimeDataConnector",
                "batch_identifiers": ["batch_id"],
            }
        },
    }
)

batch_request = RuntimeBatchRequest(
    datasource_name="spark_datasource",
    data_connector_name="runtime_connector",
    data_asset_name="bronze",
    runtime_parameters={"batch_data": df},
    batch_identifiers={"batch_id": "validate_bronze"},
)

context.add_or_update_expectation_suite("bronze_suite")
validator = context.get_validator(
    batch_request=batch_request,
    expectation_suite_name="bronze_suite",
)

# World Bank record shape: country {id,value}, indicator {id,value}, date, value, _ingested_at
validator.expect_table_row_count_to_be_between(min_value=1)
validator.expect_table_columns_to_match_set(
    column_set=["country", "indicator", "date", "value", "_ingested_at"]
)
# We set this ourselves unconditionally in job_bronze_ingest.py - if it's
# ever null, something upstream of us silently broke
validator.expect_column_values_to_not_be_null(column="_ingested_at")

results = validator.validate()
logger.info(f"Bronze validation: success={results['success']}")

if not results["success"]:
    raise Exception(f"Bronze data quality validation failed: {results}")

logger.info("Bronze validation passed")
