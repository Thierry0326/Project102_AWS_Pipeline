# Project 101 / 102 — Context Primer

A self-contained context document. Paste this at the top of any new AI session
(or share with a collaborator) to bootstrap full understanding of the project
state without needing to re-derive history.

---

## 1. Author Profile

- **Background:** DBA transitioning into cloud data engineering
- **Location:** Bamenda, Cameroon — works at CHPR (health research context)
- **Platform:** Windows 11, Docker Desktop, Git Bash (MINGW64) + PowerShell, VS Code
- **AWS account:** active paid account (no Azure)
- **Constraint:** building on free / zero-cost tooling where possible
- **Working style:** console-first to build mental model, then IaC; prefers
  hands-on typing for muscle memory; values explanation + examples over
  shortcuts; documents failures as well as successes

---

## 2. Project 101 — Local ETL Pipeline (COMPLETE ✅)

End-to-end ETL pipeline for the **Stack Overflow 2020 Developer Survey**,
implementing a full Medallion Architecture (Bronze → Silver → Gold) plus a
live Grafana dashboard. Took **5 DAG runs and 23 documented bugs** to reach green.

### 2.1 Architecture

| Layer | Storage | Notes |
|---|---|---|
| Source | CSV | Stack Overflow 2020 survey, ~9.5MB ZIP, 64,461 respondents |
| Bronze (raw) | SQL Server 2022 | `stackoverflow_raw.dbo.survey_responses_raw` |
| Silver (cleaned) | MySQL 8 | `stackoverflow_processed.*` — 5 tables |
| Gold (analytical) | MySQL 8 | `stackoverflow_analytics.*` — star schema (1 fact + 2 dims) |
| Orchestration | Airflow 2.11.1 | LocalExecutor, metadata in MySQL |
| Monitoring | Grafana | Reads from MySQL + SQL Server datasources |
| CI/CD | GitHub Actions | flake8 + pytest + `docker compose config` |

### 2.2 Final Row Counts (verified loaded end-to-end)

| Table | Rows |
|---|---|
| `stackoverflow_raw.survey_responses_raw` | 64,461 |
| `stackoverflow_processed.respondents` | 64,461 |
| `stackoverflow_processed.respondent_education` | 64,461 |
| `stackoverflow_processed.respondent_compensation` | 63,693 |
| `stackoverflow_processed.respondent_technologies` | 1,157,765 |
| `stackoverflow_processed.respondent_dev_types` | 157,094 |
| `stackoverflow_analytics.dim_developer` | 64,461 |
| `stackoverflow_analytics.dim_geography` | 184 |
| `stackoverflow_analytics.fact_survey_responses` | 64,461 |
| **Total** | **1,636,580** |

### 2.3 Tech Stack — Exact Pins (DO NOT change without reading gotchas)

```
apache-airflow==2.11.1            # NOT 2.8.x (old Python), NOT 3.x (breaks DAG code)
pandas>=2.1,<2.2                  # NOT 2.2+ (silently fails with SQLAlchemy 1.4)
sqlalchemy>=1.4.54,<2.0           # NOT 2.0+ (Airflow 2.11 hard-pins via flask-appbuilder<1.5)
numpy>=1.26,<2.3
pymssql==2.3.13
PyMySQL==1.1.2
pyodbc==5.3.0
great-expectations==0.18.22       # NOT 1.x (breaking API rewrite)
python-dotenv==1.1.0
openpyxl==3.1.5
pytest==8.3.5
pytest-cov==5.0.0
loguru==0.7.3
tqdm==4.67.3
colorama==0.4.6
```

Base Docker image: `apache/airflow:2.11.1-python3.12`

### 2.4 DAG Flow

```
start → extract_data → load_to_sqlserver → transform_data → load_to_mysql
      → validate_pipeline → notify_success → end
```

**Important rule:** each task does ONLY its own stage. Do NOT have downstream
tasks re-run `run_extraction()` or `run_load()`. Each task reads disk/DB
state that the previous task persisted.

### 2.5 Container Layout

| Service | Container name | Role |
|---|---|---|
| `sqlserver` | `project101_sqlserver` | MSSQL 2022 Bronze layer |
| `mysql` | `project101_mysql` | MySQL 8 Silver/Gold + Airflow metadata |
| `grafana` | `project101_grafana` | Dashboard UI at :3000 |
| `airflow-init` | `project101_airflow_init` | One-shot db migrate + admin user |
| `airflow-webserver` | `project101_airflow_webserver` | Airflow UI at :8080 |
| `airflow-scheduler` | `project101_airflow_scheduler` | DAG parser + task executor |

### 2.6 Verified Reference Credentials (as of last green run)

| Service | User | Password |
|---|---|---|
| SQL Server | `sa` | `Pro101Mssql123` |
| MySQL root | `root` | `pro101mysql123` |
| MySQL app user | `project101_user` | `pro101mysql123` |
| Airflow admin | `admin` | `admin123` |
| Grafana admin | `admin` | `admin123` |

### 2.7 Critical Gotchas (top 5 — full list in `docs/TROUBLESHOOTING.md`)

1. **Pandas 2.2 silently breaks with SQLAlchemy 1.4.** Pin `pandas<2.2`.
2. **MSSQL 18456 "Login Failed" often masks "database does not exist."**
   Always grep `/var/opt/mssql/log/errorlog` for the real reason.
3. **MSSQL volume bakes the SA password on FIRST boot only.** Either
   `ALTER LOGIN sa` in-place or drop the volume.
4. **MySQL TRUNCATE blocked by FK constraints** on every re-run. Toggle
   `SET FOREIGN_KEY_CHECKS = 0` inside `engine.begin()`.
5. **Git Bash on Windows mangles container paths.** Fix: leading `//` or
   `MSYS_NO_PATHCONV=1`.

### 2.8 Grafana Dashboard (COMPLETE ✅)

10-panel dashboard — "Project 101 — Stack Overflow Developer Survey 2020":
- Row 1 (KPIs): Total Respondents · Countries · Avg Salary · Bronze Rows
- Row 2 (Compensation): Top 15 Countries by Salary · Salary by Experience
- Row 3 (Technologies): Top 20 Languages · Developer Types pie
- Row 4 (Geography): Respondents by Country · Country summary table

⚠️ Dashboards live in `grafana_data` Docker volume only — not yet exported
to JSON. Will be lost on `docker compose down -v`.

### 2.9 What's NOT Done in Project 101

- `education_key` and `compensation_key` on `fact_survey_responses` are NULL
- No automated backups
- Grafana dashboards not exported to JSON in repo
- DBA ops dashboard partially started

---

## 3. Project 102 — AWS Cloud-Native Pipeline (IN PROGRESS 🔄)

### 3.1 Repository

- **GitHub:** `github.com/Thierry0326/Project102_AWS_Pipeline`
- **Status:** Phases 0–3 built, deployed, and verified end-to-end against real
  AWS resources. Phase 4 written and validated but deliberately left disabled.

### 3.1b Actual Implementation Status (as of 2026-07-10)

The plan below in 3.9 was the original design. What actually got built used a
condensed phase numbering (0–4, matching the git commit history) rather than
the original 0–9 breakdown — some steps merged, some (data quality
validation, CDK, MWAA) haven't been built yet. **`README.md` is the
authoritative as-built reference** (architecture diagram, cost breakdown,
bugs fixed, how to run); this section is a quick pointer, not a duplicate.

| Phase | Status | What it actually is |
|---|---|---|
| 0 — Foundation | ✅ Done | S3 remote state (native S3 locking, not DynamoDB), budget alarms, Terraform skeleton |
| 1 — Storage & Network | ✅ Done | 3 S3 buckets w/ versioning+lifecycle, VPC + private subnets + S3 Gateway Endpoint + Glue SG, Secrets Manager configs |
| 2 — Glue ETL | ✅ Done | 3 PySpark Glue jobs (bronze_ingest/silver_transform/gold_model), Glue IAM role, Data Catalog + 5 crawlers |
| 3 — Orchestration | ✅ Done, verified live | Step Functions (5 states: 3 Glue jobs → 5 parallel crawlers → SNS notify), retry/catch on every state |
| 4 — Scheduling | ⏸️ Built, disabled | EventBridge daily-cron rule in `eventbridge.tf`, commented out on purpose — pipeline only runs when triggered manually |
| — Data quality validation | ⬜ Not built | Great Expectations / Glue DQ states between layers — planned in 3.6 below, not implemented |
| — CDK | ⬜ Not built | Terraform only |
| — CI/CD | ⬜ Not built | Deploys are manual `terraform apply` |
| — Grafana/Power BI dashboards | ⬜ Not built | Athena queries verified working manually; no dashboard yet |

**Verified working:** a full green execution completed in ~8m47s; SNS
success email received; Athena queries against the Gold star schema confirmed
working. 5 real bugs were found and fixed getting there (urllib3 version
mismatch, a flaky upstream API, invalid AWS tag characters, a Step Functions
JSONPath nesting bug, and a misleading execution-status bug) — full list in
`README.md`.

### 3.2 Project Statement

> "Build a flexible serverless AWS pipeline that ingests any World Bank
> development indicator on demand, so analysts can explore relationships
> between economic, health, and education data across 200+ countries
> and 30+ years."

**This pipeline answers two analytical questions:**

**Dashboard 1 — African Development Trends**
*"How have GDP, life expectancy, and education spending changed across
African countries over the last 30 years, and how does Cameroon compare
to regional peers?"*

**Dashboard 2 — Health Spending vs Outcomes**
*"What is the relationship between health expenditure per capita and key
health outcomes (mortality rates, life expectancy) across low and middle
income countries?"*

### 3.3 Data Source — World Bank API

- **URL:** `https://api.worldbank.org/v2/country/{country}/indicator/{indicator}?format=json`
- **Authentication:** None required (fully public)
- **Format:** JSON
- **Coverage:** 200+ countries, 1960–2024

**Indicators to ingest:**

| Indicator Code | Metric | Dashboard |
|---|---|---|
| `NY.GDP.PCAP.CD` | GDP per capita (USD) | A + B |
| `SP.DYN.LE00.IN` | Life expectancy at birth | A + B |
| `SH.XPD.CHEX.PC.CD` | Health expenditure per capita | B |
| `SE.XPD.TOTL.GD.ZS` | Education spending (% of GDP) | A |
| `SP.POP.TOTL` | Total population | A |
| `SH.DYN.MORT` | Child mortality rate | B |
| `SI.POV.DDAY` | Poverty headcount ratio | A |
| `SP.DYN.IMRT.IN` | Infant mortality rate | B |

### 3.4 Architecture — Project 101 vs Project 102

The same Medallion Architecture, every tool replaced by its AWS equivalent.
Status column added post-build — see 3.1b for the full picture:

| Project 101 (Local Docker) | Project 102 (AWS Serverless) | Status |
|---|---|---|
| Stack Overflow CSV | World Bank API (JSON) | ✅ built |
| SQL Server (Bronze) | S3 Bronze (raw JSON) | ✅ built |
| `transform.py` in Docker | AWS Glue PySpark Job | ✅ built |
| MySQL Silver (5 tables) | S3 Silver (cleaned Parquet) | ✅ built |
| MySQL Gold (star schema) | S3 Gold (dimensional Parquet) | ✅ built |
| `mysql_schema.sql` | Glue Data Catalog | ✅ built |
| MySQL Workbench queries | Amazon Athena (SQL on S3) | ✅ built, verified |
| Airflow DAG (8 tasks) | Step Functions (5 states) | ✅ built, verified live |
| Airflow cron schedule | EventBridge Rule (daily cron) | ⏸️ built, disabled |
| `notify_success` task | SNS email notification | ✅ built, verified |
| `.env` file | AWS Secrets Manager | ✅ built |
| `docker-compose.yml` | Terraform | ✅ built (CDK not built) |
| GitHub Actions (tests) | GitHub Actions (plan + deploy) | ⬜ not built |
| Great Expectations | Great Expectations + Glue DQ | ⬜ not built |
| Grafana → MySQL | Grafana → Athena / Power BI | ⬜ not built |

**Key insight:** From a data analyst's perspective Athena IS the database.
They connect Power BI or Grafana to Athena exactly like a SQL database.
The fact that data sits as Parquet files in S3 underneath is invisible to them.

### 3.5 Gold Layer Data Model

**As actually built** (`glue_jobs/job_gold_model.py`) — leaner than the
original design below: no `region`/`income_group` on `dim_country`, no
`category` on `dim_indicator`. Those fields aren't populated by the World
Bank API response and were dropped rather than faked.

```sql
dim_country
    country_id      INT (PK, surrogate)
    country_code    VARCHAR   -- e.g. "CMR"
    country_name    VARCHAR   -- e.g. "Cameroon"

dim_indicator
    indicator_id    INT (PK, surrogate)
    indicator_code  VARCHAR   -- e.g. "SP.DYN.LE00.IN"
    indicator_name  VARCHAR   -- e.g. "Life expectancy at birth"

dim_year
    year_id         INT (PK, surrogate)
    year            INT       -- e.g. 2023
    decade          INT       -- e.g. 2020 (floor(year/10)*10)

fact_world_bank
    fact_id         STRING (PK, uuid)
    country_id      INT (FK → dim_country)
    indicator_id    INT (FK → dim_indicator)
    year_id         INT (FK → dim_year)
    value           DOUBLE
    _ingested_at    STRING (ISO timestamp)
```

If `region`/`income_group`/`category` enrichment is wanted later, it'd need
a separate reference dataset (World Bank's country metadata endpoint, or a
static lookup) joined in during the Gold build — not something the
indicator API responses carry.

### 3.6 Pipeline Architecture Flow

⚠️ **This was the original design.** The data quality validation states
(2, 4, 6 below) were never built — the actual Step Functions definition
goes straight Ingest → Transform → Transform → Crawl → Notify, 5 states
total, no GE/DQ gates between layers. EventBridge is a classic
`aws_cloudwatch_event_rule`, not "EventBridge Scheduler", and it's disabled.
See `infrastructure/terraform/state_machine/pipeline.asl.json` and the
architecture diagram in `README.md` for the as-built flow. Kept below as
the target design if validation states get added later.

```
EventBridge Scheduler (daily cron)
        ↓
Step Functions State Machine
        ↓
┌----------------------------------------------────────────────┐
│ State 1: Ingest          World Bank API → S3 Bronze (JSON)   │
│ State 2: Validate Bronze  Great Expectations — row count,    │
│                           file integrity, no empty responses │
│ State 3: Transform Silver Glue Job → S3 Silver (Parquet)     │
│                           clean, normalize, type-cast        │
│ State 4: Validate Silver  Glue Data Quality — null rates,    │
│                           value ranges, expected columns     │
│ State 5: Transform Gold   Glue Job → S3 Gold (Parquet)       │
│                           build dim_country, dim_indicator,  │
│                           dim_year, fact_world_bank          │
│ State 6: Validate Gold    Glue Data Quality — FK integrity,  │
│                           fact row counts, dim stability     │
│ State 7: Crawl & Catalog  Glue Crawler → Glue Data Catalog   │
│                           all 3 layers registered + queryable│
│ State 8: Notify           SNS → success email                │
└----------------------------------------------────────────────┘
        ↓ (on ANY state failure)
SNS Failure Alert → email immediately
        ↓
Local Grafana → Athena → S3 Gold
Power BI → Athena → S3 Gold (analyst access)
```

### 3.7 Learning Philosophy

**Anchor every AWS service to Project 101:**

| AWS Service | Project 101 Equivalent | What AWS adds |
|---|---|---|
| S3 | `data/raw/` folder | Distributed, durable, 11 nines availability |
| Glue | `transform.py` | Managed infra, no Docker, scales automatically |
| Step Functions | Airflow DAG | State machine, built-in retry, zero server |
| IAM | `.env` + Linux file permissions | Centralized, auditable, rotatable |
| VPC | Docker network | Spans data centers, fine-grained routing |
| CloudWatch | `logs/` directory | Queryable, alertable, retained |
| Secrets Manager | `.env` file | Rotation, audit trail, no git exposure |
| Athena | MySQL Workbench | Serverless SQL, no DB server, pay per query |
| Glue Data Catalog | `mysql_schema.sql` | Auto-inferred, central, versioned |
| EventBridge | Airflow schedule_interval | Serverless cron, no scheduler process |
| SNS | `notify_success` task | Push to email/SMS/Lambda, failure routing |

**The 5 primitive concepts — classify every service:**

| Concept | Services in this project |
|---|---|
| Storage | S3 |
| Compute | Glue |
| Networking | VPC, Security Groups, S3 Gateway Endpoint |
| Identity | IAM Roles, Secrets Manager |
| Observability | CloudWatch, SNS |

**Before provisioning any resource, complete this sentence:**
*"I'm using X because without it, Y would happen."*
If you can't finish it, you don't need X.

**IaC learning order per phase:**
1. Draw it (boxes + arrows before opening console)
2. Click it (console, read docs for every field)
3. Terraform it (encode it, destroy console version first)
4. CDK it (port to Python CDK constructs)
5. Write it up (LinkedIn post or README before next phase)

### 3.8 When to Use Serverless vs Other Models

**Serverless wins when:**
- Workload runs on a schedule or triggered by events
- Runtime is minutes not hours
- Load is unpredictable or bursty
- Small team, low ops capacity

**EC2/containers win when:**
- Always-on application (web server, API)
- Runtime exceeds 15 min to hours
- Need SSH access for debugging
- Steady predictable load (reserved instances cheaper)

**Our pipeline is serverless because:** it runs once daily, each job
takes minutes, nothing needs to be always-on. Zero cost when idle.

### 3.9 Phased Plan (original 0–9 design)

This is the plan as originally scoped. **It was not followed 1:1** — see
3.1b for what was actually built, under a condensed 0–4 numbering. Rough
mapping: original phases 0–1 → actual Phase 0–1; original 2–4 (ingest,
Bronze→Silver, Silver→Gold, all with GE/DQ validation) → actual Phase 2
(built without the validation steps); original phase 5 → actual Phase 3
(Step Functions built; EventBridge from phase 5 became actual Phase 4,
disabled); original phases 6–9 (CloudWatch dashboard, Grafana, CI/CD, MWAA)
are not built.

| Phase | Focus | Est. cost | Status |
|---|---|---|---|
| 0 | Budget alarms set · IAM setup · Terraform skeleton · CDK skeleton | Free | ✅ done (CDK skeleton skipped) |
| 1 | S3 buckets (3-tier) · lifecycle rules · VPC + S3 Gateway Endpoint · Secrets Manager | ~$0 | ✅ done |
| 2 | World Bank API → S3 Bronze · Glue Crawler · Athena query · GE validation | ~$0 | ✅ done (GE validation skipped) |
| 3 | Glue job: Bronze → Silver Parquet · Glue DQ rules | ~$0.01/run | ✅ done (DQ rules skipped) |
| 4 | Glue job: Silver → Gold Parquet · dim/fact build · Glue DQ rules | ~$0.01/run | ✅ done (DQ rules skipped) |
| 5 | Step Functions state machine + EventBridge daily cron · end-to-end test | Free | ✅ Step Functions verified live; EventBridge built but disabled |
| 6 | SNS failure alerts · CloudWatch 7-day retention · CloudWatch dashboard | Free | ✅ SNS alerts verified; CloudWatch dashboard not built |
| 7 | Local Grafana → Athena · Dashboard 1 (Africa trends) · Dashboard 2 (Health) | Free | ⬜ not built |
| 8 | GitHub Actions: PR → plan/diff · merge → apply/deploy | Free | ⬜ not built |
| 9 | *(optional)* MWAA 1-week experiment · document vs Step Functions · destroy | ~$20 | ⬜ not started (folded into Project 103 plan) |

**Current status as of 2026-07-10: Phases 0–3 complete and verified,
Phase 4 built but disabled. AWS resources were live and idle-cost-verified
(~$0.80/mo) through this point, then torn down via `terraform destroy`
at the end of this work session per the habit below.**

### 3.10 Cost Traps — Handle on Day One

- ✅ **AWS Budgets alarm** — done
- ✅ **NAT Gateway = $32/mo minimum** — avoided; S3 Gateway Endpoint (free)
  used instead. Tradeoff: Glue jobs aren't wired into the private VPC as a
  result (Bronze Ingest needs public internet for the World Bank API) — see
  3.1b and `vpc.tf` comments.
- ⬜ **CloudWatch log retention** — Glue jobs log via `--enable-continuous-cloudwatch-log`; explicit 7-day retention on the log group not yet set
- ✅ **S3 lifecycle rules** — Bronze → Glacier IR after 30 days, done
- ✅ **`terraform destroy` habit** — practiced at the end of this work session (see 3.9)
- ⬜ **Free tier cliffs** — avoid RDS and EC2 for core pipeline (n/a so far — no RDS/EC2 used)

### 3.11 Monthly Cost Estimate

Real numbers, verified against an actual run (see `README.md` for the full
breakdown) rather than the original pre-build estimate:

| Service | Monthly cost | Notes |
|---|---|---|
| S3 (3 buckets) | ~$0.01 | Current data volume |
| AWS Glue (3 jobs + 5 crawlers per run) | ~$0.07–0.19/run | Only incurred when manually triggered — no schedule active |
| Amazon Athena (queries) | ~$0.01 | Pay-per-query, negligible at this volume |
| Step Functions, SNS | Free tier | |
| Secrets Manager (2 secrets) | ~$0.80/mo | **Dominant idle cost** — the only thing billed with zero pipeline activity |
| **Idle total (no schedule, as currently deployed)** | **~$0.80/mo** | |
| **If Phase 4 daily schedule is enabled** | **~$1.50–3/mo** | ~$0.15/run × 30 days + idle cost |

**Verified full run:** ~8m47s wall-clock, 3 Glue jobs + 5 crawlers, well
under a cent in Glue DPU charges per the actual job-run DPU-hours observed.

---

## 4. Project 103 — Lift and Shift (PLANNED, NOT STARTED)

After Project 102, migrate Project 101 to AWS using traditional servers:

| Component | AWS Service |
|---|---|
| SQL Server (Bronze) | RDS SQL Server |
| MySQL (Silver/Gold) | RDS MySQL |
| Airflow | MWAA |
| Grafana | EC2 |

**Purpose:** learn EC2, RDS, MWAA; understand cost difference vs serverless;
produce a 3-way comparison (local Docker vs serverless AWS vs EC2/RDS AWS)
for LinkedIn and portfolio.

**Estimated cost:** ~$100/month (spin up, document, tear down quickly)

---

## 5. How to Use This Document

When starting a new AI session, paste this file at the top with:

> "Here's the full context for my project. Read this first, then I'll
> tell you what I want to work on next."

**When continuing Project 102, also state:**
- Which phase you are on
- What was the last thing completed
- Whether Terraform/CDK has been initialized
- Whether the $1 budget alarm has triggered (means something is running)

---

## 6. Repo Structure (Project 102 — as actually built)

CDK, `validation/`, a top-level `step_functions/` dir, and `.github/workflows/`
were part of the original target and were never created — Terraform-only,
no CDK; no data quality validation; no CI/CD yet.

```
Project102_AWS_Pipeline/
├── glue_jobs/
│   ├── job_bronze_ingest.py      # World Bank API → S3 Bronze
│   ├── job_silver_transform.py   # Bronze JSON → Silver Parquet
│   └── job_gold_model.py         # Silver → Gold star schema
├── infrastructure/terraform/
│   ├── backend.tf                # S3 remote state (native S3 locking)
│   ├── main.tf                   # Provider + default tags
│   ├── variables.tf / outputs.tf
│   ├── s3.tf                     # Bronze/Silver/Gold buckets
│   ├── vpc.tf                    # Private subnets, S3 Gateway Endpoint (unused by Glue - see 3.1b)
│   ├── secrets.tf                # Secrets Manager configs
│   ├── glue.tf / glue_iam.tf / glue_crawler.tf
│   ├── s3_glue_scripts_append.tf # Glue script bucket + aws_s3_object uploads
│   ├── sns.tf                    # Success/failure topics
│   ├── step_functions.tf         # State machine + IAM
│   ├── eventbridge.tf            # Daily schedule - commented out, not applied
│   └── state_machine/pipeline.asl.json
├── PROJECT_CONTEXT.md            # This file
├── PROJECT_CONTEXT_Mermaid.md / project102_mermaid.md  # Architecture diagrams
├── TROUBLESHOOTING.md            # Phase 0-1 issue log
├── Change_to_md.py / claude_codebase.md  # Codebase-dump utility for AI chat sessions
├── .gitignore
└── README.md                     # As-built architecture, cost, how-to-run
```

---

## 7. Key Files Reference (Project 101 → Project 102, actual mapping)

| Project 101 file | Ported into Project 102 as |
|---|---|
| `pipeline/extract.py` | `glue_jobs/job_bronze_ingest.py` |
| `pipeline/transform.py` | `glue_jobs/job_silver_transform.py` |
| `pipeline/load_mysql.py` | `glue_jobs/job_gold_model.py` |
| `dags/etl_pipeline.py` | `infrastructure/terraform/state_machine/pipeline.asl.json` |
| `docs/TROUBLESHOOTING.md` | `TROUBLESHOOTING.md` (Phase 0-1 issues; Phase 2-3 bugs logged in `README.md` instead) |

---

_Last updated: 2026-07-10_
_Status: Project 101 complete ✅ | Project 102 Phases 0-3 complete & verified ✅, Phase 4 built but disabled ⏸️ | Project 103 planned ⬜_
_Dataset P101: Stack Overflow 2020 Developer Survey_
_Dataset P102: World Bank Development Indicators API_
_Maintainer: Thierry — github.com/Thierry0326_
_AWS resources for Project 102 were torn down via `terraform destroy` at the end of the 2026-07-10 session — re-run `terraform apply` to redeploy before resuming._
