"""
job_validate_silver.py
Data quality gate for S3 Silver (cleaned Parquet)

Project 101 equivalent: the validate_pipeline task in the Airflow DAG,
but per-layer instead of once at the end
What AWS adds: nothing here - same Great Expectations library as
               job_validate_bronze.py, checking the cleaned/typed output
               instead of the raw JSON

Catches: the Silver transform silently producing garbage - a corrupted
year value, a schema drift, or a catastrophic row-count drop that a
"job succeeded" status alone wouldn't reveal (Glue only fails on an
exception, not on "technically ran but produced nonsense")
"""
import sys

import great_expectations as gx
from great_expectations.core.batch import RuntimeBatchRequest

from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext

args = getResolvedOptions(sys.argv, [
    "JOB_NAME",
    "SILVER_BUCKET",
])

sc = SparkContext()
glue_context = GlueContext(sc)
spark = glue_context.spark_session
logger = glue_context.get_logger()

SILVER_BUCKET = args["SILVER_BUCKET"]
silver_path = f"s3://{SILVER_BUCKET}/worldbank/"

logger.info(f"Reading silver from {silver_path}")
df = spark.read.parquet(silver_path)

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
    data_asset_name="silver",
    runtime_parameters={"batch_data": df},
    batch_identifiers={"batch_id": "validate_silver"},
)

context.add_or_update_expectation_suite("silver_suite")
validator = context.get_validator(
    batch_request=batch_request,
    expectation_suite_name="silver_suite",
)

validator.expect_table_row_count_to_be_between(min_value=1)
validator.expect_table_columns_to_match_set(
    column_set=[
        "country_id", "country_name", "indicator_id", "indicator_name",
        "year", "value", "_ingested_at",
    ]
)
validator.expect_column_values_to_not_be_null(column="country_id")
validator.expect_column_values_to_not_be_null(column="indicator_id")
# Loose bound, not tied to the exact configured date_range_start/end in
# Secrets Manager - this is a sanity check against a corrupted/miscast
# year (e.g. a negative number or a parsing artifact), not a business
# rule enforcement, so it's deliberately wider than the real 1990-2024
# ingest range.
validator.expect_column_values_to_be_between(column="year", min_value=1960, max_value=2030)

results = validator.validate()
logger.info(f"Silver validation: success={results['success']}")

if not results["success"]:
    raise Exception(f"Silver data quality validation failed: {results}")

logger.info("Silver validation passed")
