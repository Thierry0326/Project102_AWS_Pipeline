"""
job_bronze_ingest.py
World Bank API → S3 Bronze (raw JSONL)

Project 101 equivalent: pipeline/extract.py
What AWS adds: runs serverless on Glue, secrets from Secrets Manager,
               output lands directly in S3 — no local disk needed
"""
import sys
import json
import time
import boto3
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
from datetime import datetime, timezone

from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext

args = getResolvedOptions(sys.argv, [
    "JOB_NAME",
    "BRONZE_BUCKET",
    "PIPELINE_SECRET_ARN",
    "WORLDBANK_SECRET_ARN",
])

sc = SparkContext()
glue_context = GlueContext(sc)
logger = glue_context.get_logger()

secrets = boto3.client("secretsmanager", region_name="us-east-1")

wb_config = json.loads(
    secrets.get_secret_value(SecretId=args["WORLDBANK_SECRET_ARN"])["SecretString"]
)

BASE_URL    = wb_config["api_base_url"]          # https://api.worldbank.org/v2
PER_PAGE    = int(wb_config["per_page"])          # 1000
INDICATORS  = wb_config["indicators"]             # list of 8 codes
DATE_START  = wb_config["date_range_start"]       # "1990"
DATE_END    = wb_config["date_range_end"]         # "2024"
BRONZE_BUCKET = args["BRONZE_BUCKET"]

run_date    = datetime.now(timezone.utc).strftime("%Y-%m-%d")
ingested_at = datetime.now(timezone.utc).isoformat()

s3 = boto3.client("s3")

# World Bank API can be slow for large paginated responses (200+ countries × 30 years).
# Retry on transient 5xx errors and connection issues; read timeout raised to 120s.
_retry = Retry(
    total=3,
    backoff_factor=2,          # waits 2s, 4s, 8s between retries
    # World Bank's API intermittently 400s on well-formed, valid requests
    # (confirmed by re-fetching a failed URL seconds later and getting 200)
    # - it's flaky, not us, so 400 is included here alongside the usual 5xx set.
    status_forcelist=[400, 500, 502, 503, 504],
    # not passing allowed_methods/method_whitelist: the kwarg name changed
    # between urllib3 versions and Glue 4.0's bundled urllib3 predates
    # allowed_methods. GET is already in urllib3's default retry-safe set.
)
_session = requests.Session()
_session.mount("https://", HTTPAdapter(max_retries=_retry))


def fetch_indicator(indicator_code: str) -> list:
    """Page through the World Bank API for one indicator, return all records."""
    records = []
    page = 1
    total_pages = None

    url = f"{BASE_URL}/country/all/indicator/{indicator_code}"
    params = {
        "format":   "json",
        "per_page": PER_PAGE,
        "date":     f"{DATE_START}:{DATE_END}",
    }

    while total_pages is None or page <= total_pages:
        params["page"] = page
        response = _session.get(url, params=params, timeout=120)
        response.raise_for_status()

        envelope = response.json()
        meta       = envelope[0]
        page_data  = envelope[1] if len(envelope) > 1 and envelope[1] else []

        if total_pages is None:
            total_pages = int(meta["pages"])
            logger.info(
                f"[{indicator_code}] total={meta['total']} pages={total_pages}"
            )

        for record in page_data:
            record["_ingested_at"] = ingested_at
            records.append(record)

        if not page_data:
            break

        page += 1

    return records


for indicator in INDICATORS:
    logger.info(f"Fetching {indicator}")
    try:
        records = fetch_indicator(indicator)
    except Exception as exc:
        logger.error(f"Failed to fetch {indicator}: {exc}")
        raise

    # Write as JSONL (one JSON object per line) — Spark reads this natively
    # with spark.read.json(); a JSON array file is unreliable across versions.
    jsonl_bytes = "\n".join(json.dumps(r, default=str) for r in records).encode()

    s3_key = f"worldbank/raw/{run_date}/{indicator}/data.json"
    s3.put_object(
        Bucket=BRONZE_BUCKET,
        Key=s3_key,
        Body=jsonl_bytes,
        ContentType="application/json",
    )
    logger.info(f"Written {len(records)} records → s3://{BRONZE_BUCKET}/{s3_key}")

logger.info("Bronze ingest complete")
