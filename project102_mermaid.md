# Project 102 — Architecture Diagrams (Mermaid)

---

## Diagram 1 — Full Pipeline Architecture (Main Diagram)

```mermaid
flowchart TD
    classDef aws fill:#FF9900,stroke:#232F3E,color:#232F3E,font-weight:bold
    classDef storage fill:#3F8624,stroke:#232F3E,color:#fff,font-weight:bold
    classDef compute fill:#E7157B,stroke:#232F3E,color:#fff,font-weight:bold
    classDef orchestration fill:#E7157B,stroke:#232F3E,color:#fff,font-weight:bold
    classDef security fill:#DD344C,stroke:#232F3E,color:#fff,font-weight:bold
    classDef observe fill:#E7157B,stroke:#232F3E,color:#fff,font-weight:bold
    classDef external fill:#1A73E8,stroke:#232F3E,color:#fff,font-weight:bold
    classDef iac fill:#6B2D8B,stroke:#232F3E,color:#fff,font-weight:bold
    classDef viz fill:#00897B,stroke:#232F3E,color:#fff,font-weight:bold

    %% External Source
    WB["🌍 World Bank\nPublic API\n200+ countries\n8 indicators\n1990–2024"]:::external

    %% IaC & CI/CD
    subgraph CICD["⚙️ CI/CD & Infrastructure as Code"]
        GH["GitHub Actions\nPR → terraform plan\nMerge → terraform apply"]:::iac
        TF["Terraform\nProvisions all AWS resources"]:::iac
        CDK["AWS CDK (Python)\nSame infra, higher abstraction"]:::iac
        GH --> TF
        GH --> CDK
    end

    %% Security Layer
    subgraph SEC["🔐 Identity & Security (runs under everything)"]
        IAM["IAM Roles\nLeast-privilege per service\nNo shared credentials"]:::security
        SM["Secrets Manager\nReplaces .env file\nRotation + audit trail"]:::security
        VPC["VPC + S3 Gateway Endpoint\nPrivate network\nFree — no NAT Gateway"]:::security
    end

    %% Trigger
    EB["⏰ EventBridge Scheduler\nDaily cron trigger\n(Replaces Airflow schedule_interval)"]:::aws

    %% Orchestration
    SF["🧠 AWS Step Functions\nState Machine — 8 states\n(Replaces Airflow DAG)\nBuilt-in retry + failure routing"]:::orchestration

    EB --> SF

    %% Pipeline States
    subgraph PIPELINE["📦 Data Pipeline — Step Functions States"]
        direction TB
        ST1["State 1: Ingest\nGlue Python Shell Job\nWorld Bank API → S3 Bronze\nRaw JSON files"]:::compute
        ST2["State 2: Validate Bronze\nGreat Expectations\nRow count ≥ expected\nFile integrity check"]:::compute
        ST3["State 3: Transform Silver\nGlue Python Shell Job\nClean + normalize\nJSON → Parquet"]:::compute
        ST4["State 4: Validate Silver\nGlue Data Quality Rules\nNull rates, value ranges\nExpected columns"]:::compute
        ST5["State 5: Transform Gold\nGlue Python Shell Job\nBuild dim + fact tables\nParquet star schema"]:::compute
        ST6["State 6: Validate Gold\nGlue Data Quality Rules\nFK integrity\nFact row counts"]:::compute
        ST7["State 7: Crawl & Catalog\nGlue Crawler\nScan all 3 S3 layers\nUpdate Data Catalog"]:::compute
        ST8["State 8: Notify Success\nSNS Email\nPipeline complete"]:::compute

        ST1 --> ST2 --> ST3 --> ST4 --> ST5 --> ST6 --> ST7 --> ST8
    end

    SF --> PIPELINE

    %% Storage Layers
    subgraph STORAGE["🪣 Storage — S3 Medallion Architecture"]
        direction LR
        BR["S3 Bronze\np102-bronze/\nRaw JSON\nGlacier after 30 days\n(Replaces SQL Server)"]:::storage
        SL["S3 Silver\np102-silver/\nCleaned Parquet\n5 normalized tables\n(Replaces MySQL Silver)"]:::storage
        GL["S3 Gold\np102-gold/\nDimensional Parquet\ndim_country\ndim_indicator\ndim_year\nfact_world_bank\n(Replaces MySQL Gold)"]:::storage
        CAT["Glue Data Catalog\nSchema registry\nAll 3 layers registered\n(Replaces mysql_schema.sql)"]:::compute

        BR --> SL --> GL --> CAT
    end

    %% Data flows into storage
    ST1 --> BR
    ST3 --> SL
    ST5 --> GL
    ST7 --> CAT

    %% Failure routing
    FAIL["❌ Any State Fails\nStep Functions catches error"]
    SNS_FAIL["SNS Failure Alert\nImmediate email notification"]
    PIPELINE --> FAIL
    FAIL --> SNS_FAIL

    %% Query + Visualization
    ATH["🔍 Amazon Athena\nServerless SQL over S3\nPay per query ~cents\n(Replaces MySQL Workbench)"]:::aws
    CAT --> ATH

    subgraph VIZ["📊 Visualization Layer"]
        GRAF["Local Grafana\nDashboard 1: Africa Trends\nDashboard 2: Health vs Outcomes\n(Same Docker container as P101)"]:::viz
        PBI["Power BI\nAnalyst access\nODBC → Athena connector"]:::viz
    end

    ATH --> VIZ

    %% Observability
    subgraph OBS["👁️ Observability"]
        CW["CloudWatch\nAll Glue job logs\n7-day retention\nExecution metrics"]:::observe
        SNS_OK["SNS Success\nEmail on pipeline complete"]:::observe
    end

    PIPELINE --> CW
    ST8 --> SNS_OK

    %% Security wraps everything
    SEC -.->|secures| PIPELINE
    SEC -.->|secures| STORAGE
    CICD -.->|provisions| SEC
    CICD -.->|provisions| STORAGE

    WB --> ST1
```

---

## Diagram 2 — Medallion Architecture (Data Layers Only)

```mermaid
flowchart LR
    API["🌍 World Bank API\nJSON Response\n{country, indicator,\nyear, value}"]

    subgraph BRONZE["🥉 Bronze Layer — S3"]
        B1["raw_gdp_per_capita.json"]
        B2["raw_life_expectancy.json"]
        B3["raw_health_expenditure.json"]
        B4["raw_education_spending.json"]
        B5["raw_population.json"]
        B6["... 3 more indicators"]
    end

    subgraph SILVER["🥈 Silver Layer — S3 Parquet"]
        S1["countries.parquet\n200+ rows\ncode, name, region\nincome_group"]
        S2["indicators.parquet\n8 rows\ncode, name, category"]
        S3["observations.parquet\n~300,000 rows\ncountry, indicator\nyear, value (cleaned)"]
    end

    subgraph GOLD["🥇 Gold Layer — S3 Parquet"]
        G1["dim_country.parquet\ncountry_id, code\nname, region\nincome_group"]
        G2["dim_indicator.parquet\nindicator_id, code\nname, category"]
        G3["dim_year.parquet\nyear_id, year\ndecade"]
        G4["fact_world_bank.parquet\nfact_id\ncountry_id FK\nindicator_id FK\nyear_id FK\nvalue, loaded_at"]
    end

    ATH["Amazon Athena\nSQL queries\non Parquet files"]

    API -->|"Glue Ingest Job\nState 1"| BRONZE
    BRONZE -->|"Glue Transform Job\nState 3"| SILVER
    SILVER -->|"Glue Transform Job\nState 5"| GOLD
    GOLD --> ATH

    ATH -->|"Dashboard 1"| D1["Africa Development\nTrends\n(Cameroon focus)"]
    ATH -->|"Dashboard 2"| D2["Health Spending\nvs Outcomes"]
```

---

## Diagram 3 — Step Functions State Machine Flow

```mermaid
stateDiagram-v2
    [*] --> Ingest: EventBridge cron fires

    Ingest --> ValidateBronze: JSON saved to S3 Bronze
    ValidateBronze --> TransformSilver: GE checks pass
    TransformSilver --> ValidateSilver: Parquet saved to S3 Silver
    ValidateSilver --> TransformGold: Glue DQ rules pass
    TransformGold --> ValidateGold: Parquet saved to S3 Gold
    ValidateGold --> CrawlAndCatalog: DQ rules pass
    CrawlAndCatalog --> NotifySuccess: Catalog updated
    NotifySuccess --> [*]: SNS email sent

    Ingest --> FailureAlert: Glue job fails
    ValidateBronze --> FailureAlert: Validation fails
    TransformSilver --> FailureAlert: Glue job fails
    ValidateSilver --> FailureAlert: DQ rules fail
    TransformGold --> FailureAlert: Glue job fails
    ValidateGold --> FailureAlert: DQ rules fail
    CrawlAndCatalog --> FailureAlert: Crawler fails
    FailureAlert --> [*]: SNS failure email sent
```

---

## Diagram 4 — Project 101 vs Project 102 Comparison

```mermaid
flowchart LR
    subgraph P101["🐳 Project 101 — Local Docker"]
        direction TB
        A1["Stack Overflow CSV"]
        A2["SQL Server\n(Bronze)"]
        A3["transform.py\n(Docker container)"]
        A4["MySQL Silver\n(5 tables)"]
        A5["MySQL Gold\n(star schema)"]
        A6["Airflow DAG\n(8 tasks)"]
        A7["Grafana\n→ MySQL"]
        A1 --> A2 --> A3 --> A4 --> A5
        A6 -.->|orchestrates| A3
        A5 --> A7
    end

    subgraph P102["☁️ Project 102 — AWS Serverless"]
        direction TB
        B1["World Bank API\n(JSON)"]
        B2["S3 Bronze\n(raw JSON)"]
        B3["AWS Glue Jobs\n(managed Python)"]
        B4["S3 Silver\n(Parquet)"]
        B5["S3 Gold\n(Parquet)"]
        B6["Step Functions\n(8 states)"]
        B7["Grafana / Power BI\n→ Athena → S3"]
        B1 --> B2 --> B3 --> B4 --> B5
        B6 -.->|orchestrates| B3
        B5 --> B7
    end

    A1 -.->|"replaced by"| B1
    A2 -.->|"replaced by"| B2
    A3 -.->|"replaced by"| B3
    A4 -.->|"replaced by"| B4
    A5 -.->|"replaced by"| B5
    A6 -.->|"replaced by"| B6
    A7 -.->|"replaced by"| B7
```
