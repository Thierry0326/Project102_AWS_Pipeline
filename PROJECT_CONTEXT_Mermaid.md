# Project 101 / 102 — Full Context & Architecture Guide

A self-contained reference document combining project context, architecture
descriptions, data models, and visual diagrams. Paste this at the top of any
new AI session to bootstrap full understanding without re-deriving history.

---

## 📋 Table of Contents

1. [Author Profile](#1-author-profile)
2. [Project 101 — Local ETL Pipeline](#2-project-101--local-etl-pipeline-complete-)
3. [Project 102 — AWS Cloud-Native Pipeline](#3-project-102--aws-cloud-native-pipeline-in-progress-)
4. [Project 103 — Lift and Shift (Planned)](#4-project-103--lift-and-shift-planned)
5. [How to Use This Document](#5-how-to-use-this-document)

---

## 1. Author Profile

| Field | Detail |
|---|---|
| **Background** | DBA transitioning into cloud data engineering |
| **Location** | Bamenda, Cameroon — works at CHPR (health research) |
| **Platform** | Windows 11, Docker Desktop, Git Bash (MINGW64), VS Code |
| **AWS Account** | Active paid account (no Azure) |
| **Constraint** | Free / zero-cost tooling where possible |
| **Working style** | Console-first → IaC; hands-on typing; explains before building; documents failures |

---

## 2. Project 101 — Local ETL Pipeline (COMPLETE ✅)

End-to-end ETL pipeline for the **Stack Overflow 2020 Developer Survey**,
implementing a full Medallion Architecture (Bronze → Silver → Gold) plus a
live Grafana dashboard. Took **5 DAG runs and 23 documented bugs** to reach green.

### 2.1 High-Level Architecture

```mermaid
flowchart TD
    SRC["📄 Stack Overflow 2020\nCSV File — 9.5MB ZIP\n64,461 respondents"]

    subgraph DOCKER["🐳 Docker Environment (Local Machine)"]
        direction TB
        SS["SQL Server 2022\n🥉 Bronze Layer\nstackoverflow_raw\nsurvey_responses_raw"]
        PY["Python — transform.py\nSQLAlchemy + pandas\nClean + restructure data"]
        MY["MySQL 8\n🥈 Silver Layer\nstackoverflow_processed\n5 cleaned tables"]
        GOLD["MySQL 8\n🥇 Gold Layer\nstackoverflow_analytics\nStar schema"]
        AF["Apache Airflow 2.11.1\nOrchestration — 8 tasks\nLocalExecutor"]
        GR["Grafana\n10-panel dashboard\nPort 3000"]
        CI["GitHub Actions\nCI/CD — flake8 + pytest"]
    end

    SRC -->|"extract.py\ndownload + parse"| SS
    SS -->|"transform.py\nSQLAlchemy reads"| PY
    PY -->|"load_mysql.py\nbatch insert"| MY
    MY -->|"Gold logic\nbuild dim + fact"| GOLD
    AF -.->|"orchestrates all tasks"| PY
    GOLD --> GR
    CI -.->|"tests on every push"| DOCKER
```

### 2.2 DAG Flow (8 Tasks)

```mermaid
flowchart LR
    T1([start]) --> T2[extract_data]
    T2 --> T3[load_to_sqlserver]
    T3 --> T4[transform_data]
    T4 --> T5[load_to_mysql]
    T5 --> T6[validate_pipeline]
    T6 --> T7[notify_success]
    T7 --> T8([end])

    style T1 fill:#4CAF50,color:#fff
    style T8 fill:#4CAF50,color:#fff
    style T2 fill:#2196F3,color:#fff
    style T3 fill:#FF9800,color:#fff
    style T4 fill:#9C27B0,color:#fff
    style T5 fill:#009688,color:#fff
    style T6 fill:#F44336,color:#fff
    style T7 fill:#607D8B,color:#fff
```

> ⚠️ **Rule:** Each task does ONLY its own stage. Never re-run upstream logic
> in a downstream task — this caused redundant 9.5MB downloads and 10+ min
> durations when broken.

### 2.3 Medallion Architecture — Data Layers

```mermaid
flowchart LR
    subgraph BRONZE["🥉 Bronze — SQL Server"]
        B["survey_responses_raw\n64,461 rows\nNVARCHAR(MAX) for\nmulti-value columns\nuntouched raw data"]
    end

    subgraph SILVER["🥈 Silver — MySQL"]
        S1["respondents\n64,461 rows"]
        S2["respondent_education\n64,461 rows"]
        S3["respondent_compensation\n63,693 rows"]
        S4["respondent_technologies\n1,157,765 rows"]
        S5["respondent_dev_types\n157,094 rows"]
    end

    subgraph GOLD["🥇 Gold — MySQL Star Schema"]
        F["fact_survey_responses\n64,461 rows"]
        D1["dim_developer\n64,461 rows"]
        D2["dim_geography\n184 rows"]
        F --> D1
        F --> D2
    end

    BRONZE -->|"transform.py\nclean + normalize"| SILVER
    SILVER -->|"Gold logic\nbuild dimensions + fact"| GOLD
```

### 2.4 Final Row Counts

| Table | Layer | Rows |
|---|---|---|
| `survey_responses_raw` | Bronze | 64,461 |
| `respondents` | Silver | 64,461 |
| `respondent_education` | Silver | 64,461 |
| `respondent_compensation` | Silver | 63,693 |
| `respondent_technologies` | Silver | 1,157,765 |
| `respondent_dev_types` | Silver | 157,094 |
| `dim_developer` | Gold | 64,461 |
| `dim_geography` | Gold | 184 |
| `fact_survey_responses` | Gold | 64,461 |
| **TOTAL** | | **1,636,580** |

### 2.5 Container Layout

```mermaid
flowchart TD
    subgraph CONTAINERS["Docker Services — docker-compose.yml"]
        SS["project101_sqlserver\nMSSQL 2022\nPort 1434→1433\nBronze layer"]
        MY["project101_mysql\nMySQL 8\nPort 3307→3306\nSilver + Gold + Airflow metadata"]
        AI["project101_airflow_init\nOne-shot: db migrate\n+ create admin user\nExits after done"]
        AW["project101_airflow_webserver\nAirflow UI\nPort 8080"]
        AS["project101_airflow_scheduler\nDAG parser\nTask executor"]
        GR["project101_grafana\nDashboard UI\nPort 3000"]
    end

    AI -->|"condition: completed successfully"| AW
    AI -->|"condition: completed successfully"| AS
    AW & AS -->|"reads/writes metadata"| MY
    AS -->|"executes tasks against"| SS
    AS -->|"executes tasks against"| MY
    GR -->|"queries dashboards"| MY
    GR -->|"queries dashboards"| SS
```

> YAML anchors (`&airflow_env` / `*airflow_env`) share env + volumes across
> the 3 Airflow services to avoid duplication.

### 2.6 Tech Stack — Exact Pins

```
apache-airflow==2.11.1        # NOT 2.8.x, NOT 3.x
pandas>=2.1,<2.2              # NOT 2.2+ — silently fails with SQLAlchemy 1.4
sqlalchemy>=1.4.54,<2.0       # NOT 2.0+ — Airflow 2.11 hard-pins this
numpy>=1.26,<2.3
pymssql==2.3.13
PyMySQL==1.1.2
pyodbc==5.3.0
great-expectations==0.18.22   # NOT 1.x — breaking API rewrite
python-dotenv==1.1.0
openpyxl==3.1.5
pytest==8.3.5
pytest-cov==5.0.0
loguru==0.7.3
tqdm==4.67.3
colorama==0.4.6
```

Base Docker image: `apache/airflow:2.11.1-python3.12`

### 2.7 Top 5 Critical Gotchas

> Full list of 23 issues in `docs/TROUBLESHOOTING.md`

| # | Issue | Fix |
|---|---|---|
| 1 | Pandas 2.2 silently fails with SQLAlchemy 1.4 — empty tables, no error | Pin `pandas<2.2` |
| 2 | MSSQL 18456 "Login Failed" masks "database does not exist" | Grep `/var/opt/mssql/log/errorlog` for real reason |
| 3 | MSSQL volume bakes SA password on first boot only — `.env` changes ignored | `ALTER LOGIN sa` in-place or drop volume |
| 4 | MySQL TRUNCATE blocked by FK constraints on every re-run | `SET FOREIGN_KEY_CHECKS=0` inside `engine.begin()` |
| 5 | Git Bash mangles container paths (`/opt/` → `C:/Program Files/Git/opt/`) | Use leading `//` or `MSYS_NO_PATHCONV=1` |

### 2.8 Grafana Dashboard — 10 Panels

```mermaid
flowchart TD
    subgraph DASH["📊 Project 101 Grafana Dashboard"]
        subgraph ROW1["Row 1 — KPI Stats"]
            P1["Total Respondents\n64,461"]
            P2["Countries\n183"]
            P3["Avg Salary\n$87,705"]
            P4["Bronze Rows\n64,461"]
        end
        subgraph ROW2["Row 2 — Compensation"]
            P5["Top 15 Countries\nby Avg Salary\n(Bar chart)"]
            P6["Salary by Years\nof Experience\n(Line chart)"]
        end
        subgraph ROW3["Row 3 — Technologies"]
            P7["Top 20 Languages\nCurrently Used\n(Horizontal bar)"]
            P8["Top Developer\nTypes\n(Pie chart)"]
        end
        subgraph ROW4["Row 4 — Geography"]
            P9["Respondents\nby Country\n(Bar chart)"]
            P10["Country Summary\nTable\n(country + salary)"]
        end
    end

    MY_SRC["MySQL Gold\nstackoverflow_analytics"] -->|"queries"| DASH
    SS_SRC["SQL Server Bronze\nstackoverflow_raw"] -->|"queries"| DASH
```

> ⚠️ Dashboards live in `grafana_data` Docker volume only — not exported
> to JSON yet. Will be lost on `docker compose down -v`.

### 2.9 Port Mapping Reference

| Service | Windows Port | Docker Internal |
|---|---|---|
| SQL Server | 1434 | 1433 |
| MySQL | 3307 | 3306 |
| Airflow UI | 8080 | 8080 |
| Grafana | 3000 | 3000 |

### 2.10 Verified Credentials (last green run)

| Service | User | Password |
|---|---|---|
| SQL Server | `sa` | `Pro101Mssql123` |
| MySQL root | `root` | `pro101mysql123` |
| MySQL app | `project101_user` | `pro101mysql123` |
| Airflow | `admin` | `admin123` |
| Grafana | `admin` | `admin123` |

### 2.11 What Is NOT Done in Project 101

- `education_key` and `compensation_key` on `fact_survey_responses` are NULL
- No automated database backups
- Grafana dashboards not exported to JSON in the repo
- DBA ops monitoring dashboard partially started

---

## 3. Project 102 — AWS Cloud-Native Pipeline (IN PROGRESS 🔄)

**GitHub Repo:** `github.com/Thierry0326/Project102_AWS_Pipeline`

### 3.1 Project Statement

> *"Build a flexible serverless AWS pipeline that ingests any World Bank
> development indicator on demand, so analysts can explore relationships
> between economic, health, and education data across 200+ countries
> and 30+ years."*

**This pipeline powers two analytical dashboards:**

| Dashboard | Question |
|---|---|
| **Dashboard 1 — Africa Trends** | How have GDP, life expectancy, and education spending changed across African countries over 30 years — and how does Cameroon compare to regional peers? |
| **Dashboard 2 — Health vs Outcomes** | What is the relationship between health expenditure per capita and health outcomes (mortality, life expectancy) across low and middle income countries? |

### 3.2 Project 101 vs Project 102 — Side by Side

```mermaid
flowchart LR
    subgraph P101["🐳 Project 101 — Local Docker"]
        direction TB
        A1["Stack Overflow CSV"]
        A2["SQL Server\nBronze"]
        A3["transform.py\nDocker container"]
        A4["MySQL Silver\n5 tables"]
        A5["MySQL Gold\nstar schema"]
        A6["Airflow DAG\n8 tasks"]
        A7["Grafana → MySQL"]
        A1 --> A2 --> A3 --> A4 --> A5
        A6 -.->|orchestrates| A3
        A5 --> A7
    end

    subgraph P102["☁️ Project 102 — AWS Serverless"]
        direction TB
        B1["World Bank API\nJSON"]
        B2["S3 Bronze\nraw JSON"]
        B3["AWS Glue Jobs\nmanaged Python"]
        B4["S3 Silver\nParquet"]
        B5["S3 Gold\nParquet"]
        B6["Step Functions\n8 states"]
        B7["Grafana + Power BI\n→ Athena → S3"]
        B1 --> B2 --> B3 --> B4 --> B5
        B6 -.->|orchestrates| B3
        B5 --> B7
    end

    A1 -.->|replaced by| B1
    A2 -.->|replaced by| B2
    A3 -.->|replaced by| B3
    A4 -.->|replaced by| B4
    A5 -.->|replaced by| B5
    A6 -.->|replaced by| B6
    A7 -.->|replaced by| B7
```

### 3.3 AWS Service Mapping to Project 101

| AWS Service | Project 101 Equivalent | What AWS adds |
|---|---|---|
| S3 | `data/raw/` folder | Distributed, 11-nines durable, lifecycle policies |
| Glue Job | `transform.py` | Managed infra, no Docker, auto-scales |
| Step Functions | Airflow DAG | State machine, built-in retry, serverless |
| EventBridge | Airflow `schedule_interval` | Serverless cron, no scheduler process |
| IAM Roles | `.env` + Linux permissions | Centralized, auditable, rotatable |
| Secrets Manager | `.env` file | Rotation, audit trail, no git exposure |
| VPC | Docker network | Spans data centers, fine-grained routing |
| CloudWatch | `logs/` directory | Queryable, alertable, 7-day retention |
| Athena | MySQL Workbench queries | Serverless SQL, no DB server, pay per query |
| Glue Data Catalog | `mysql_schema.sql` | Auto-inferred, central schema registry |
| SNS | `notify_success` task | Failure + success alerts, push to email |
| Glue Data Quality | `validate_pipeline` task | Declarative rules, integrated with catalog |
| Great Expectations | Same — ported from P101 | Row counts, file integrity, null checks |

### 3.4 The 5 Primitive Cloud Concepts

```mermaid
mindmap
  root((Cloud\nPrimitives))
    Storage
      S3 Bronze
      S3 Silver
      S3 Gold
    Compute
      Glue Ingest Job
      Glue Silver Job
      Glue Gold Job
      Glue Crawler
    Networking
      VPC
      Security Groups
      S3 Gateway Endpoint
    Identity
      IAM Roles
      Secrets Manager
    Observability
      CloudWatch Logs
      CloudWatch Dashboard
      SNS Alerts
```

### 3.5 Data Source — World Bank API

| Field | Detail |
|---|---|
| **URL** | `https://api.worldbank.org/v2/country/{country}/indicator/{indicator}?format=json` |
| **Authentication** | None — fully public |
| **Response format** | JSON |
| **Coverage** | 200+ countries, 1960–2024 |
| **Cost** | Free, unlimited |

**Indicators to ingest:**

| Indicator Code | Metric | Dashboard |
|---|---|---|
| `NY.GDP.PCAP.CD` | GDP per capita (USD) | 1 + 2 |
| `SP.DYN.LE00.IN` | Life expectancy at birth | 1 + 2 |
| `SH.XPD.CHEX.PC.CD` | Health expenditure per capita | 2 |
| `SE.XPD.TOTL.GD.ZS` | Education spending (% of GDP) | 1 |
| `SP.POP.TOTL` | Total population | 1 |
| `SH.DYN.MORT` | Child mortality rate | 2 |
| `SI.POV.DDAY` | Poverty headcount ratio | 1 |
| `SP.DYN.IMRT.IN` | Infant mortality rate | 2 |

### 3.6 Medallion Architecture — Data Layers

```mermaid
flowchart LR
    API["🌍 World Bank API\nJSON Response"]

    subgraph BRONZE["🥉 Bronze — S3\np102-bronze/"]
        direction TB
        BJ1["raw_NY.GDP.PCAP.CD.json"]
        BJ2["raw_SP.DYN.LE00.IN.json"]
        BJ3["raw_SH.XPD.CHEX.PC.CD.json"]
        BJ4["... 5 more indicators"]
        BNOTE["Untouched raw JSON\nExactly as API returned\nGlacier after 30 days"]
    end

    subgraph SILVER["🥈 Silver — S3\np102-silver/"]
        direction TB
        SP1["countries.parquet\n200+ rows\ncode, name, region\nincome_group"]
        SP2["indicators.parquet\n8 rows\ncode, name, category"]
        SP3["observations.parquet\n~300,000 rows\ncountry, indicator\nyear, value (cleaned)"]
        SNOTE["Cleaned + normalized\nType-cast values\nNulls handled"]
    end

    subgraph GOLD["🥇 Gold — S3\np102-gold/"]
        direction TB
        G1["dim_country.parquet"]
        G2["dim_indicator.parquet"]
        G3["dim_year.parquet"]
        G4["fact_world_bank.parquet"]
        GNOTE["Dimensional model\nReady for analytics\nAthena queryable"]
    end

    CAT["Glue Data Catalog\nSchema registry\nAll layers registered"]
    ATH["Amazon Athena\nServerless SQL\nPay per query"]

    API -->|"Glue Ingest\n+ GE Validation"| BRONZE
    BRONZE -->|"Glue Transform\n+ Glue DQ"| SILVER
    SILVER -->|"Glue Transform\n+ Glue DQ"| GOLD
    GOLD --> CAT --> ATH
```

### 3.7 Gold Layer — Star Schema Data Model

```mermaid
erDiagram
    dim_country {
        int country_id PK
        varchar country_code
        varchar country_name
        varchar region
        varchar income_group
    }

    dim_indicator {
        int indicator_id PK
        varchar indicator_code
        varchar indicator_name
        varchar category
    }

    dim_year {
        int year_id PK
        int year
        varchar decade
    }

    fact_world_bank {
        int fact_id PK
        int country_id FK
        int indicator_id FK
        int year_id FK
        float value
        timestamp loaded_at
    }

    dim_country ||--o{ fact_world_bank : "has many"
    dim_indicator ||--o{ fact_world_bank : "has many"
    dim_year ||--o{ fact_world_bank : "has many"
```

### 3.8 Full Pipeline Architecture

```mermaid
flowchart TD
    %% External
    WB["🌍 World Bank Public API\n200+ countries · 8 indicators · 1990–2024\nFree · No authentication"]

    %% CI/CD
    subgraph CICD["⚙️ CI/CD & Infrastructure as Code"]
        GH["GitHub Actions\nPR → terraform plan + cdk diff\nMerge → terraform apply + cdk deploy"]
        TF["Terraform\nProvisions all AWS resources"]
        CDK["AWS CDK (Python)\nSame infra, higher abstraction\nLearned after Terraform"]
        GH --> TF & CDK
    end

    %% Security
    subgraph SEC["🔐 Identity & Security"]
        IAM["IAM Roles\nLeast-privilege per service\nGlue role · Step Functions role\nNo shared credentials"]
        SM["Secrets Manager\nReplaces .env file\nRotation + audit trail"]
        VPC["VPC + S3 Gateway Endpoint\nPrivate routing to S3\nFree — avoids $32/mo NAT Gateway"]
    end

    %% Trigger
    EB["⏰ EventBridge Scheduler\nDaily cron trigger\nReplaces Airflow schedule_interval\nCompletely free"]

    %% Step Functions
    SF["🧠 AWS Step Functions\nState Machine — 8 states\nReplaces entire Airflow DAG\nBuilt-in retry + failure routing"]

    EB --> SF

    %% Pipeline
    subgraph PIPELINE["📦 Data Pipeline — 8 Step Functions States"]
        direction TB
        ST1["State 1: Ingest\nGlue Python Shell Job\nWorld Bank API → S3 Bronze\nRaw JSON saved"]
        ST2["State 2: Validate Bronze\nGreat Expectations\nRow count · file integrity\nNo truncated responses"]
        ST3["State 3: Transform Silver\nGlue Python Shell Job\nClean + normalize + type-cast\nJSON → Parquet"]
        ST4["State 4: Validate Silver\nGlue Data Quality Rules\nNull rates · value ranges\nExpected columns present"]
        ST5["State 5: Transform Gold\nGlue Python Shell Job\nBuild dim_country · dim_indicator\ndim_year · fact_world_bank"]
        ST6["State 6: Validate Gold\nGlue Data Quality Rules\nFK integrity · fact row counts\nDim row stability"]
        ST7["State 7: Crawl and Catalog\nGlue Crawler\nScans all 3 S3 layers\nUpdates Glue Data Catalog"]
        ST8["State 8: Notify Success\nSNS Topic\nEmail — pipeline complete"]

        ST1 --> ST2 --> ST3 --> ST4 --> ST5 --> ST6 --> ST7 --> ST8
    end

    SF --> PIPELINE

    %% Storage
    subgraph STORAGE["🪣 S3 Medallion Storage"]
        BR["S3 Bronze\np102-bronze/\nRaw JSON\nGlacier after 30 days"]
        SL["S3 Silver\np102-silver/\nCleaned Parquet\n5 normalized tables"]
        GL["S3 Gold\np102-gold/\nDimensional Parquet\ndim + fact tables"]
        CAT["Glue Data Catalog\nSchema registry\nAll 3 layers queryable"]
        BR --> SL --> GL --> CAT
    end

    ST1 --> BR
    ST3 --> SL
    ST5 --> GL
    ST7 --> CAT

    %% Failure path
    FAIL["❌ Step Functions\nCatch — any state fails"]
    SNS_F["SNS Failure Alert\nImmediate email sent"]
    PIPELINE --> FAIL --> SNS_F

    %% Query
    ATH["🔍 Amazon Athena\nServerless SQL over S3 Gold\nPay per query — cents at our scale\nReplaces MySQL Workbench"]
    CAT --> ATH

    %% Visualization
    subgraph VIZ["📊 Visualization Layer"]
        GRAF["Local Grafana\nDashboard 1: Africa Development Trends\nDashboard 2: Health Spending vs Outcomes\nSame Docker container as Project 101"]
        PBI["Power BI\nODBC → Athena connector\nAnalyst self-service access"]
    end
    ATH --> VIZ

    %% Observability
    subgraph OBS["👁️ Observability"]
        CW["CloudWatch\nAll Glue job logs\n7-day retention\nExecution metrics dashboard"]
        SNS_OK["SNS Success\nEmail on pipeline complete"]
    end
    PIPELINE --> CW
    ST8 --> SNS_OK

    %% Cross-cutting
    SEC -.->|secures| PIPELINE
    SEC -.->|secures| STORAGE
    CICD -.->|provisions| SEC
    CICD -.->|provisions| STORAGE

    WB --> ST1
```

### 3.9 Step Functions State Machine Flow

```mermaid
stateDiagram-v2
    [*] --> Ingest : EventBridge cron fires daily

    Ingest --> ValidateBronze : JSON landed in S3 Bronze
    ValidateBronze --> TransformSilver : GE checks passed
    TransformSilver --> ValidateSilver : Parquet saved to S3 Silver
    ValidateSilver --> TransformGold : Glue DQ rules passed
    TransformGold --> ValidateGold : Parquet saved to S3 Gold
    ValidateGold --> CrawlAndCatalog : DQ rules passed
    CrawlAndCatalog --> NotifySuccess : Data Catalog updated
    NotifySuccess --> [*] : Success email sent via SNS

    Ingest --> FailureAlert : Glue job error
    ValidateBronze --> FailureAlert : Row count or file check fails
    TransformSilver --> FailureAlert : Glue job error
    ValidateSilver --> FailureAlert : DQ rule violation
    TransformGold --> FailureAlert : Glue job error
    ValidateGold --> FailureAlert : DQ rule violation
    CrawlAndCatalog --> FailureAlert : Crawler error
    FailureAlert --> [*] : Failure email sent via SNS
```

### 3.10 Data Validation Strategy

```mermaid
flowchart LR
    subgraph V1["Bronze Validation\nGreat Expectations"]
        R1["✅ Row count ≥ expected\nper indicator per country"]
        R2["✅ File not empty\nor truncated"]
        R3["✅ Required JSON fields\npresent in response"]
    end

    subgraph V2["Silver Validation\nGlue Data Quality"]
        R4["✅ Null rate < 20%\non value column"]
        R5["✅ Year range\n1990 ≤ year ≤ 2024"]
        R6["✅ Country codes\nmatch ISO standard"]
        R7["✅ All 8 indicators\npresent in output"]
    end

    subgraph V3["Gold Validation\nGlue Data Quality"]
        R8["✅ FK integrity\nall country_id valid"]
        R9["✅ fact_world_bank rows\nmatch Silver observations"]
        R10["✅ dim_country rows\nstable 200+ countries"]
        R11["✅ No duplicate\nfact records"]
    end

    subgraph V4["Pipeline Level\nStep Functions Catch"]
        R12["✅ Any state failure\nroutes to SNS alert"]
        R13["✅ Pipeline halts\non first failure"]
        R14["✅ No silent failures —\nfail loud always"]
    end

    V1 -->|passes| V2 -->|passes| V3 -->|passes| V4
```

### 3.11 Phased Delivery Plan

```mermaid
gantt
    title Project 102 — Phased Delivery
    dateFormat  YYYY-MM-DD
    section Foundation
    Phase 0 - Budget + IAM + IaC Skeleton    :active, p0, 2026-05-04, 2d
    section Infrastructure
    Phase 1 - S3 + VPC + Secrets Manager     :p1, after p0, 2d
    section Ingestion
    Phase 2 - World Bank API + Bronze + Athena :p2, after p1, 2d
    section Transform
    Phase 3 - Silver Glue Job + Validation   :p3, after p2, 3d
    Phase 4 - Gold Glue Job + Validation     :p4, after p3, 2d
    section Orchestration
    Phase 5 - Step Functions + EventBridge   :p5, after p4, 3d
    section Monitoring
    Phase 6 - SNS + CloudWatch               :p6, after p5, 1d
    section Visualization
    Phase 7 - Grafana + Power BI → Athena    :p7, after p6, 2d
    section CI/CD
    Phase 8 - GitHub Actions Deploy Pipeline :p8, after p7, 1d
    section Optional
    Phase 9 - MWAA Experiment (1 week)       :p9, after p8, 7d
```

### 3.12 Phase Checklist

| Phase | Focus | Cost | Status |
|---|---|---|---|
| 0 | Budget alarms · IAM · Terraform skeleton · CDK skeleton | Free | 🔄 In progress |
| 1 | S3 buckets · lifecycle rules · VPC · S3 Gateway Endpoint · Secrets Manager | ~$0 | ⬜ |
| 2 | World Bank API → S3 Bronze · Glue Crawler · Athena · GE validation | ~$0 | ⬜ |
| 3 | Glue job: Bronze → Silver Parquet · Glue DQ rules | ~$0.01/run | ⬜ |
| 4 | Glue job: Silver → Gold Parquet · dim/fact build · Glue DQ | ~$0.01/run | ⬜ |
| 5 | Step Functions state machine · EventBridge cron · end-to-end test | Free | ⬜ |
| 6 | SNS alerts · CloudWatch 7-day retention · CloudWatch dashboard | Free | ⬜ |
| 7 | Local Grafana → Athena · Dashboard 1 · Dashboard 2 · Power BI | Free | ⬜ |
| 8 | GitHub Actions: PR → plan/diff · merge → apply/deploy | Free | ⬜ |
| 9 | MWAA 1-week experiment · document vs Step Functions · destroy | ~$20 | ⬜ |

**Phase 0 progress:**
- ✅ AWS account active (paid)
- ✅ Budget alarms set ($1 zero-spend + $10 forecast)
- ✅ GitHub repo created: `Project102_AWS_Pipeline`
- ✅ `.gitignore` configured (Python template)
- ⬜ IAM setup — **next step**
- ⬜ Terraform installed + skeleton
- ⬜ CDK installed + skeleton

### 3.13 Cost Traps — Handle Early

| Trap | Risk | Fix |
|---|---|---|
| NAT Gateway | $32/month minimum | Use S3 Gateway Endpoint (free) |
| CloudWatch log retention | Grows forever by default | Set every log group to 7 days |
| RDS instances | Free tier expires at 12 months | Use S3 + Athena instead |
| Glue Dev Endpoints | ~$0.44/hr when running | Never use — use Glue jobs instead |
| MWAA environment | ~$50-80/mo minimum | Use Step Functions (Phase 9 only if needed) |
| Terraform state in git | Exposes secrets | Use S3 remote backend + DynamoDB lock |

### 3.14 Monthly Cost Estimate

| Service | Estimated Monthly |
|---|---|
| S3 (all 3 buckets + state) | ~$0.01 |
| AWS Glue (2 jobs, daily) | ~$0.50 |
| Amazon Athena (queries) | ~$0.01 |
| Step Functions | Free tier |
| EventBridge Scheduler | Free tier |
| SNS | Free tier |
| CloudWatch | Free tier |
| Secrets Manager | ~$0.80 |
| **Total** | **~$1.50–3/month** |

### 3.15 Repo Structure (Target)

```
Project102_AWS_Pipeline/
├── infrastructure/
│   ├── terraform/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── backend.tf          # S3 remote state + DynamoDB lock
│   └── cdk/
│       ├── app.py
│       └── stacks/
├── glue_jobs/
│   ├── ingest.py               # World Bank API → S3 Bronze
│   ├── transform_silver.py     # Bronze → Silver Parquet
│   └── transform_gold.py       # Silver → Gold Parquet (dim + fact)
├── validation/
│   ├── great_expectations/     # Bronze + Silver GE checks
│   └── glue_dq_rules/          # Silver + Gold Glue DQ rules
├── step_functions/
│   └── state_machine.json      # Step Functions definition
├── .github/
│   └── workflows/
│       └── deploy.yml          # CI/CD pipeline
├── docs/
│   ├── PROJECT_CONTEXT.md      # This file
│   └── TROUBLESHOOTING.md      # Issues + fixes log
├── .env.example                # Template only — never real secrets
├── .gitignore                  # Python + Terraform + CDK
└── README.md
```

### 3.16 Learning Philosophy

```mermaid
flowchart LR
    DRAW["1️⃣ Draw it\nBoxes + arrows\nbefore opening console"]
    CLICK["2️⃣ Click it\nBuild in AWS console\nRead docs for every field"]
    TF["3️⃣ Terraform it\nEncode what you built\nDestroy console version"]
    CDK["4️⃣ CDK it\nPort to Python constructs\nCompare abstraction levels"]
    WRITE["5️⃣ Write it up\nLinkedIn post or README\nbefore next phase"]

    DRAW --> CLICK --> TF --> CDK --> WRITE --> DRAW
```

> **Before every resource:** *"I'm using X because without it, Y would happen."*
> If you can't finish that sentence — you don't need X.

---

## 4. Project 103 — Lift and Shift (PLANNED ⬜)

After Project 102 is complete, migrate Project 101 to AWS using
traditional always-on servers to understand the cost and ops difference.

```mermaid
flowchart TD
    subgraph P103["Project 103 — Lift and Shift to AWS EC2/RDS"]
        SS["RDS SQL Server\nBronze layer\n~$25/month"]
        MY["RDS MySQL\nSilver + Gold\n~$15/month"]
        AF["MWAA\nManaged Airflow\n~$50-80/month"]
        EC["EC2 t3.small\nGrafana\n~$8/month"]
        SS --> MY
        AF -.->|orchestrates| MY
        MY --> EC
    end

    COST["💰 Total: ~$100/month\nSpin up · Document · Tear down\nPurpose: learn EC2 + RDS + MWAA"]
    P103 --> COST
```

**Purpose:** Produce a 3-way comparison for LinkedIn:

> *"I built the same pipeline three ways —
> local Docker, serverless AWS, and EC2/RDS AWS.
> Here's what I learned about cost, ops, and tradeoffs."*

---

## 5. How to Use This Document

### Starting a New AI Session

Paste this file at the top with:
> *"Here's the full project context. Read this first, then I'll tell you
> what I want to work on next."*

### When Continuing Project 102

Always state:
- Which phase you are on
- What was the last thing completed
- Whether Terraform/CDK has been initialized
- Whether the $1 zero-spend budget has triggered (means something is running)

### What Git Stores vs What Lives in AWS

```mermaid
flowchart LR
    subgraph GIT["✅ Goes to GitHub (instructions)"]
        G1["Terraform .tf files"]
        G2["CDK Python files"]
        G3["Glue job scripts .py"]
        G4["Step Functions .json"]
        G5["Great Expectations config"]
        G6["GitHub Actions workflows"]
        G7[".env.example template"]
        G8["README + docs"]
    end

    subgraph AWS["✅ Lives in AWS (actual resources)"]
        A1["S3 buckets"]
        A2["Glue jobs"]
        A3["Step Functions"]
        A4["IAM roles"]
        A5["CloudWatch logs"]
    end

    subgraph NEVER["❌ Never in Git (secrets + state)"]
        N1[".env real file"]
        N2["terraform.tfstate"]
        N3[".terraform/ folder"]
        N4["cdk.out/ folder"]
        N5["AWS credentials"]
    end

    GH_ACTIONS["GitHub Actions\nreads Git → runs Terraform\n→ creates AWS resources"]

    GIT -->|"triggers"| GH_ACTIONS
    GH_ACTIONS -->|"provisions"| AWS
```

> **Key mental model:** Git stores the **blueprint**. AWS stores the **building**.

---

_Last updated: 2026-05-04_
_Status: Project 101 complete ✅ · Project 102 Phase 0 in progress 🔄 · Project 103 planned ⬜_
_Dataset P101: Stack Overflow 2020 Developer Survey_
_Dataset P102: World Bank Development Indicators API_
_Maintainer: Thierry · github.com/Thierry0326_
