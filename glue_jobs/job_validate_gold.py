"""
job_validate_gold.py
Data quality gate for S3 Gold (star schema)

Project 101 equivalent: the validate_pipeline task in the Airflow DAG,
but per-layer instead of once at the end
What AWS adds: nothing here - same Great Expectations library as the
               other two validation jobs

Catches: the join logic in job_gold_model.py silently producing orphaned
foreign keys (a fact row pointing at a country/indicator/year that
doesn't exist in the dimension table) - the single most likely real bug
in a star-schema build, and one Glue's own "job succeeded" status can't
detect since a bad left-join just produces nulls, not an exception.
"""
import sys

import great_expectations as gx
from great_expectations.core.batch import RuntimeBatchRequest

from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext

args = getResolvedOptions(sys.argv, [
    "JOB_NAME",
    "GOLD_BUCKET",
])

sc = SparkContext()
glue_context = GlueContext(sc)
spark = glue_context.spark_session
logger = glue_context.get_logger()

GOLD_BUCKET = args["GOLD_BUCKET"]
gold_path = f"s3://{GOLD_BUCKET}/"

logger.info(f"Reading gold tables from {gold_path}")
dim_country_df = spark.read.parquet(f"{gold_path}dim_country/")
dim_indicator_df = spark.read.parquet(f"{gold_path}dim_indicator/")
dim_year_df = spark.read.parquet(f"{gold_path}dim_year/")
fact_df = spark.read.parquet(f"{gold_path}fact_world_bank/")

# Dimension tables are small (a few hundred countries, ~8 indicators,
# ~35 years) - collecting their key sets to the driver is cheap and lets
# us check the fact table's foreign keys directly, which Great
# Expectations can't do across two separate dataframes on its own.
country_ids = [r["country_id"] for r in dim_country_df.select("country_id").distinct().collect()]
indicator_ids = [r["indicator_id"] for r in dim_indicator_df.select("indicator_id").distinct().collect()]
year_ids = [r["year_id"] for r in dim_year_df.select("year_id").distinct().collect()]

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


def validate(df, asset_name, suite_name, expectations_fn):
    batch_request = RuntimeBatchRequest(
        datasource_name="spark_datasource",
        data_connector_name="runtime_connector",
        data_asset_name=asset_name,
        runtime_parameters={"batch_data": df},
        batch_identifiers={"batch_id": suite_name},
    )
    context.add_or_update_expectation_suite(suite_name)
    validator = context.get_validator(
        batch_request=batch_request,
        expectation_suite_name=suite_name,
    )
    expectations_fn(validator)
    result = validator.validate()
    logger.info(f"{asset_name} validation: success={result['success']}")
    return result


def check_dim_country(v):
    v.expect_table_row_count_to_be_between(min_value=1)
    v.expect_column_values_to_be_unique(column="country_id")


def check_dim_indicator(v):
    v.expect_table_row_count_to_be_between(min_value=1)
    v.expect_column_values_to_be_unique(column="indicator_id")


def check_dim_year(v):
    v.expect_table_row_count_to_be_between(min_value=1)
    v.expect_column_values_to_be_unique(column="year_id")


def check_fact(v):
    v.expect_table_row_count_to_be_between(min_value=1)
    v.expect_column_values_to_be_in_set(column="country_id", value_set=country_ids)
    v.expect_column_values_to_be_in_set(column="indicator_id", value_set=indicator_ids)
    v.expect_column_values_to_be_in_set(column="year_id", value_set=year_ids)


results = [
    validate(dim_country_df, "dim_country", "dim_country_suite", check_dim_country),
    validate(dim_indicator_df, "dim_indicator", "dim_indicator_suite", check_dim_indicator),
    validate(dim_year_df, "dim_year", "dim_year_suite", check_dim_year),
    validate(fact_df, "fact_world_bank", "fact_suite", check_fact),
]

failures = [r for r in results if not r["success"]]
if failures:
    raise Exception(f"Gold data quality validation failed: {failures}")

logger.info("Gold validation passed")
