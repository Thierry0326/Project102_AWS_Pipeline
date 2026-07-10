"""
job_gold_model.py
S3 Silver (Parquet) → S3 Gold (dimensional Parquet: 3 dims + 1 fact)

Project 101 equivalent: pipeline/load_mysql.py (star schema build)
What AWS adds: Parquet dims let Athena join without a database engine —
               the file layout IS the schema
"""
import sys

from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from pyspark.sql import functions as F
from pyspark.sql.window import Window

args = getResolvedOptions(sys.argv, [
    "JOB_NAME",
    "SILVER_BUCKET",
    "GOLD_BUCKET",
])

sc = SparkContext()
glue_context = GlueContext(sc)
spark = glue_context.spark_session
logger = glue_context.get_logger()

SILVER_BUCKET = args["SILVER_BUCKET"]
GOLD_BUCKET   = args["GOLD_BUCKET"]

silver_path = f"s3://{SILVER_BUCKET}/worldbank/"
gold_path   = f"s3://{GOLD_BUCKET}/"

logger.info(f"Reading silver from {silver_path}")
silver_df = spark.read.parquet(silver_path)


# ── DIM_COUNTRY ────────────────────────────────────────────────────────────────
# silver.country_id  = source code string e.g. "CMR"   → becomes country_code
# country_id in dim  = surrogate integer

dim_country_raw = silver_df.select(
    F.col("country_id").alias("country_code"),
    F.col("country_name"),
).distinct()

country_window = Window.orderBy("country_code")
dim_country = dim_country_raw.withColumn(
    "country_id", F.row_number().over(country_window)
).select("country_id", "country_code", "country_name")

logger.info(f"dim_country: {dim_country.count()} rows")


# ── DIM_INDICATOR ──────────────────────────────────────────────────────────────
dim_indicator_raw = silver_df.select(
    F.col("indicator_id").alias("indicator_code"),
    F.col("indicator_name"),
).distinct()

indicator_window = Window.orderBy("indicator_code")
dim_indicator = dim_indicator_raw.withColumn(
    "indicator_id", F.row_number().over(indicator_window)
).select("indicator_id", "indicator_code", "indicator_name")

logger.info(f"dim_indicator: {dim_indicator.count()} rows")


# ── DIM_YEAR ───────────────────────────────────────────────────────────────────
# decade = year rounded down to nearest 10, e.g. 2023 → 2020
dim_year_raw = silver_df.select("year").distinct().filter(F.col("year").isNotNull())

year_window = Window.orderBy("year")
dim_year = dim_year_raw.withColumn(
    "year_id", F.row_number().over(year_window)
).withColumn(
    "decade", (F.floor(F.col("year") / 10) * 10).cast("integer")
).select("year_id", "year", "decade")

logger.info(f"dim_year: {dim_year.count()} rows")


# ── FACT_WORLD_BANK ────────────────────────────────────────────────────────────
# Join silver to each dim to swap natural keys for surrogate keys.
# expr("uuid()") generates a random UUID per row.

fact = (
    silver_df
    .join(
        dim_country.select("country_id", "country_code"),
        silver_df["country_id"] == dim_country["country_code"],
        "left",
    )
    .join(
        dim_indicator.select("indicator_id", "indicator_code"),
        silver_df["indicator_id"] == dim_indicator["indicator_code"],
        "left",
    )
    .join(
        dim_year.select("year_id", "year"),
        silver_df["year"] == dim_year["year"],
        "left",
    )
    .select(
        F.expr("uuid()").alias("fact_id"),
        dim_country["country_id"],
        dim_indicator["indicator_id"],
        dim_year["year_id"],
        silver_df["value"],
        silver_df["_ingested_at"],
    )
)

logger.info(f"fact_world_bank: {fact.count()} rows")


# ── WRITE ───────────────────────────────────────────────────────────────────────
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "static")

def write_dim(df, name):
    path = f"{gold_path}{name}/"
    df.write.mode("overwrite").option("compression", "snappy").parquet(path)
    logger.info(f"Written {name} → {path}")

write_dim(dim_country,   "dim_country")
write_dim(dim_indicator, "dim_indicator")
write_dim(dim_year,      "dim_year")

fact_path = f"{gold_path}fact_world_bank/"
fact.write.mode("overwrite").option("compression", "snappy").parquet(fact_path)
logger.info(f"Written fact_world_bank → {fact_path}")

logger.info("Gold model complete")
