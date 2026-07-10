"""
job_silver_transform.py
S3 Bronze (raw JSONL) → S3 Silver (cleaned Parquet, partitioned by year)

Project 101 equivalent: pipeline/transform.py
What AWS adds: Glue manages the Spark cluster, Parquet is columnar so
               Athena scans less data = cheaper queries
"""
import sys

from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from pyspark.sql import functions as F
from pyspark.sql.types import IntegerType, DoubleType

args = getResolvedOptions(sys.argv, [
    "JOB_NAME",
    "BRONZE_BUCKET",
    "SILVER_BUCKET",
])

sc = SparkContext()
glue_context = GlueContext(sc)
spark = glue_context.spark_session
logger = glue_context.get_logger()

BRONZE_BUCKET = args["BRONZE_BUCKET"]
SILVER_BUCKET = args["SILVER_BUCKET"]

bronze_path = f"s3://{BRONZE_BUCKET}/worldbank/raw/"
silver_path = f"s3://{SILVER_BUCKET}/worldbank/"

logger.info(f"Reading bronze from {bronze_path}")
raw_df = spark.read.option("recursiveFileLookup", "true").json(bronze_path)

# World Bank API record shape:
#   indicator: {id: "NY.GDP.PCAP.CD", value: "GDP per capita..."}
#   country:   {id: "CMR",            value: "Cameroon"}
#   date:      "2023"
#   value:     1652.5
#   _ingested_at: "2024-01-01T00:00:00+00:00"

silver_df = raw_df.select(
    F.col("country.id").alias("country_id"),
    F.col("country.value").alias("country_name"),
    F.col("indicator.id").alias("indicator_id"),
    F.col("indicator.value").alias("indicator_name"),
    F.col("date").cast(IntegerType()).alias("year"),
    F.col("value").cast(DoubleType()).alias("value"),
    F.col("_ingested_at"),
)

# Drop rows where BOTH year and value are null — keep rows with one or the other
silver_df = silver_df.filter(
    ~(F.col("year").isNull() & F.col("value").isNull())
)

count = silver_df.count()
logger.info(f"Silver records after cleaning: {count}")

# Static overwrite: replaces the entire output path each run (full refresh)
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "static")

silver_df.write \
    .mode("overwrite") \
    .option("compression", "snappy") \
    .partitionBy("year") \
    .parquet(silver_path)

logger.info(f"Silver transform complete. {count} records → {silver_path}")
