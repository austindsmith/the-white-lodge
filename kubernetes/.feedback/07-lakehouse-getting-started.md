# The data lakehouse: what to run, and how to start collecting

You scaffolded ~60 tools across 12 categories. This document is (1) a field guide to
what each one actually does and whether you should run it, (2) the stack I'd
actually build on one VPS, and (3) a concrete first pipeline for ABQ open data, NM
legislature data, and your bills.

---

## Part 1: What all those tools do

### Object storage / file layer

| Tool | What it is | Verdict for you |
| --- | --- | --- |
| **RustFS** | S3-compatible object store, Rust MinIO alternative. Already deployed. | ✅ **Use it.** This is your data lake's floor. |
| SeaweedFS | Distributed blob store optimized for many small files | ❌ Solves a scale problem you don't have |
| Rook-Ceph | Full distributed storage (block/file/object) on K8s | ❌ Needs 3+ nodes with dedicated disks. Not viable on one VPS. |
| LakeFS | Git-like branching/commits over an S3 bucket | ⏸️ Genuinely cool, real value for "oops I broke the pipeline." Revisit at ~20 datasets. |

### Table format & catalog

A **table format** (Iceberg, Delta) turns "a pile of Parquet files in S3" into
something with schemas, ACID appends, and time travel. A **catalog** tells engines
where those tables live.

| Tool | What it is | Verdict |
| --- | --- | --- |
| **Nessie** | Iceberg catalog with git-like branches | ⏸️ Only once you commit to Iceberg |
| **Polaris** | Apache's Iceberg REST catalog (Snowflake-donated) | ⏸️ Same |
| **Hive Metastore** | The legacy catalog everything supports | ❌ Java, heavy, miserable to operate. Avoid in 2026. |

**My recommendation: skip Iceberg for now.** Iceberg pays off when you have
multiple engines reading the same tables, tables too large for one machine, or a
team. You have one machine and one person. Land raw files as Parquet in RustFS,
load into ClickHouse, and adopt Iceberg later if you outgrow it — the raw Parquet
in S3 makes that migration easy whenever you want it.

### Databases / warehouses

| Tool | What it is | Verdict |
| --- | --- | --- |
| **ClickHouse** | Columnar OLAP database. Fast analytics, great compression, superb single-node performance. Already deployed (`warehouse` + keeper, `data` ns). | ✅ **This is your warehouse.** |
| **CloudNativePG** | Postgres operator. Two clusters deployed (`apps-cluster`, `data-cluster`). | ✅ Use `data-cluster` for app state (Dagster, Metabase, dbt metadata) and small reference tables. |
| Elasticsearch | Full-text search engine | ⏸️ Only if you need fuzzy search over bill *text*. ClickHouse has decent text functions; try those first. |
| Redis | KV cache | ✅ As a dependency when a chart needs it. Not a data store. |
| Druid | Real-time OLAP for streaming | ❌ ClickHouse does this better with a tenth the operational cost |

### Query engines

| Tool | What it is | Verdict |
| --- | --- | --- |
| **DuckDB** (not scaffolded — add it) | In-process OLAP. Reads Parquet/CSV/JSON from S3 directly. No server. | ✅ **Your Swiss army knife.** Use inside Python/Jupyter for exploration and one-off transforms. |
| Trino / Presto / Starburst | Distributed federated SQL — query Postgres+S3+ClickHouse in one statement | ❌ ~4Gi minimum for a useless-ly small cluster. ClickHouse can already read Postgres and S3 directly. |
| Dremio | Trino with a UI and a semantic layer | ❌ Same, plus heavier |
| Spark | Distributed compute for data too big for one machine | ❌ Your data will fit in RAM for years |
| Flink | Stateful stream processing | ❌ No streaming use case here |

The whole `query/` category can be deleted. ClickHouse + DuckDB covers it.

### Ingestion

| Tool | What it is | Verdict |
| --- | --- | --- |
| **dlt** (not scaffolded — add it) | Python library: `pip install dlt`, write a function that yields dicts, it handles schema inference, incremental state, and loading | ✅ **Use this.** Perfect fit for scraped/API data. |
| Airbyte | 300+ prebuilt connectors, web UI. Deployed. | ⚠️ Heavy — needs Temporal (you created `temporal` + `temporal_visibility` DBs), a web server, workers, and spins a pod per sync. On a single VPS it's a lot of machinery for connectors you mostly don't need, since your sources are custom scrapes. Keep it only if you're actively using a specific connector. |
| Kafka / Redpanda / Pulsar | Streaming message buses | ❌ You are collecting batch data on a schedule |
| Debezium | Postgres CDC → Kafka | ❌ Requires Kafka |
| NiFi | Drag-and-drop flow-based ETL, JVM | ❌ Java-heavy, and its "flows" aren't really version-controllable |
| SeaTunnel | Batch/stream integration | ❌ Redundant with dlt |

### Orchestration

| Tool | What it is | Verdict |
| --- | --- | --- |
| **Dagster** | Asset-oriented orchestrator. You declare *the tables you want to exist*; it figures out the DAG. Native dbt integration, good UI, typed. Chart already in repo (commented out). | ✅ **Pick this.** The asset model matches "I want a table of ABQ crime data" much better than Airflow's task model. |
| Airflow | Task-oriented, the industry default, heavy | ⏸️ Fine, but Dagster is nicer for a solo data platform |
| Prefect | Lighter, decorator-based | ⏸️ Reasonable alternative if Dagster feels heavy |
| Kestra | YAML-declarative workflows | ⏸️ Nice if you'd rather write YAML than Python |
| Dagu | Tiny cron-with-a-DAG. Single binary. | ✅ Worth knowing about — if Dagster feels like too much on day one, Dagu + a Python script gets you collecting data *tonight*. |
| dbt | **Not an orchestrator** — a SQL transformation framework. Compiles templated SQL into DDL, manages dependencies between models, tests data. | ✅ **Essential.** Runs *inside* Dagster, not beside it. |
| Jenkins | CI server | ❌ Not a data tool |

### Quality, catalog, lineage

| Tool | What it is | Verdict |
| --- | --- | --- |
| **dbt tests** (built into dbt) | `not_null`, `unique`, `accepted_values`, custom SQL assertions | ✅ Start and probably end here |
| Great Expectations | Standalone data validation framework | ⏸️ More powerful than dbt tests, much more setup |
| DataHub / OpenMetadata / Amundsen | Enterprise data catalogs — searchable inventory of every table, owner, lineage | ❌ These are for organizations with hundreds of tables and people who need to discover each other's data. You are one person. Dagster's asset graph *is* your catalog. |
| Marquez | OpenLineage lineage collector | ❌ Same reasoning |
| Apache Atlas | Governance/lineage, Hadoop-era | ❌ No |

**Note:** you have `infrastructure/base/atlas/` deployed, which is **Ariga Atlas** —
a database schema migration tool, totally different from Apache Atlas. Worth
renaming the directory to `atlas-schema` or `ariga-atlas` to prevent exactly this
confusion later. It's a good tool; keep it for managing your warehouse DDL if you
don't let dbt own it.

### Semantic layer

| Tool | What it is | Verdict |
| --- | --- | --- |
| Cube | Defines metrics once (`total_spend = sum(amount)`) and serves them to every BI tool via API | ⏸️ Real value when you have several consumers. dbt's `metrics` / semantic models cover the basics. |
| AtScale | Commercial OLAP semantic layer | ❌ |

### Visualization

| Tool | What it is | Verdict |
| --- | --- | --- |
| **Metabase** | Point-and-click questions, dashboards, good defaults, low ceremony | ✅ **Start here.** You'll build your first chart in ten minutes. |
| Superset | More powerful, more configuration, SQL Lab is excellent | ⏸️ Graduate to it if Metabase limits you |
| Grafana | Time-series/ops dashboards | ✅ You already run it for infra. Fine for time-series data too; bad for exploration. |
| Lightdash | BI defined in dbt — charts live in your dbt project | ⏸️ Very appealing if you go all-in on dbt |
| Redash | Older, SQL-first | ❌ Metabase/Superset supersede it |
| Kibana | Elasticsearch's UI | ❌ Only with Elasticsearch |

### Notebooks / dev environment

| Tool | Verdict |
| --- | --- |
| **JupyterHub** | ✅ Multi-user notebooks. For one person, a single-user Jupyter pod (or just DuckDB locally) is lighter. |
| Coder | ⏸️ Full remote dev environments. Nice-to-have, not a data tool. |
| MLflow / Feast | ❌ Experiment tracking and a feature store. You have no ML yet. Delete until you do. |

### Management

| Tool | Verdict |
| --- | --- |
| pgAdmin4 / DBGate / Bytebase | ✅ Pick **one**. DBGate is the lightest and speaks Postgres *and* ClickHouse, which matters for you. Bytebase is schema-change-review — overkill solo. |

---

## Part 2: The stack I'd actually run

```
┌──────────────────────────────────────────────────────────────────┐
│  SOURCES                                                          │
│  ABQ open data API · Open States API · vendor portals (Playwright)│
│  your bills spreadsheet · paperless-ngx (scanned PDFs)            │
└───────────────────────────┬──────────────────────────────────────┘
                            │  dlt (Python), run as Dagster assets
                            ▼
┌──────────────────────────────────────────────────────────────────┐
│  LANDING — RustFS (S3)         s3://lake/raw/<source>/<date>/     │
│  Immutable. Exactly what the source returned. Never edited.       │
└───────────────────────────┬──────────────────────────────────────┘
                            │  dlt load
                            ▼
┌──────────────────────────────────────────────────────────────────┐
│  WAREHOUSE — ClickHouse `warehouse`                               │
│    raw_*      1:1 with source, all strings, + _loaded_at          │
│    stg_*      typed, renamed, deduped        ← dbt                │
│    dim_/fct_  modeled, joined, business logic ← dbt               │
└───────────────────────────┬──────────────────────────────────────┘
                            │
                  ┌─────────┴─────────┐
                  ▼                   ▼
            Metabase            DuckDB / Jupyter
          (dashboards)          (exploration)

     Postgres `data-cluster`: Dagster runs, Metabase app DB, dbt state
     Orchestration: Dagster  ·  Transformation: dbt  ·  Tests: dbt tests
```

**Six components**, four of which you already have running. Deploy order:

1. RustFS bucket + credentials (done — just create the `lake` bucket)
2. ClickHouse databases (done — create `raw`, `staging`, `marts`)
3. DBGate (done) — so you can look at things
4. Dagster (chart present, commented out in the overlay — enable it)
5. Metabase (filler dir exists — replace with a real HelmRelease)
6. Your dbt project (new git repo, or `kubernetes/../data/dbt/`)

Everything else in `data-lakehouse/base/` gets deleted per
[01-quick-wins.md](01-quick-wins.md).

### Where your pipeline code should live

**Not in this repo.** Create a separate `the-white-lodge-data` repo containing:

```
the-white-lodge-data/
├── pyproject.toml
├── ingest/                    # dlt sources
│   ├── abq_open_data.py
│   ├── openstates.py
│   ├── vendor_bills.py        # Playwright
│   └── bills_spreadsheet.py
├── dagster_defs/
│   ├── __init__.py
│   ├── assets.py
│   └── schedules.py
├── dbt/
│   ├── dbt_project.yml
│   ├── models/
│   │   ├── staging/
│   │   └── marts/
│   └── tests/
└── Dockerfile
```

Build it into a container in CI, and have the Dagster HelmRelease in *this* repo
reference the image tag. That separation matters: your Kubernetes repo describes
*infrastructure*, your data repo describes *pipelines*, and they change at wildly
different rates. Mixing them is a big part of why `data-lakehouse/` feels unbounded.

---

## Part 3: Getting the first data in

### Naming: resolve the "bills" collision now

You have two completely different things called bills:

- **legislative bills** (NM House/Senate bills) → call these `legislation`
- **utility/vendor bills** (your electric bill) → call these `statements` or
  `invoices`

Pick now, before you have 40 models. I'd use `legislation.*` and `finance.*` as
top-level schema names in ClickHouse.

### Source 1: Albuquerque open data (start here — easiest win)

The City of Albuquerque publishes through an ArcGIS Hub / open-data portal, and
Bernalillo County and the State publish similarly. Most ArcGIS-backed endpoints
support a REST query interface returning GeoJSON or JSON with `resultOffset`
pagination, which is trivially pageable.

A dlt source looks roughly like:

```python
import dlt
from dlt.sources.helpers import requests

@dlt.resource(name="abq_crime", write_disposition="merge", primary_key="objectid")
def abq_crime(updated_at=dlt.sources.incremental("date_reported")):
    offset, page = 0, 2000
    while True:
        r = requests.get(
            "https://<arcgis-host>/arcgis/rest/services/<layer>/FeatureServer/0/query",
            params={
                "where": f"date_reported > TIMESTAMP '{updated_at.last_value}'",
                "outFields": "*", "f": "json",
                "resultOffset": offset, "resultRecordCount": page,
            },
            timeout=60,
        )
        feats = r.json().get("features", [])
        if not feats:
            break
        yield [f["attributes"] for f in feats]
        offset += page

pipeline = dlt.pipeline(
    pipeline_name="abq", destination="clickhouse", dataset_name="raw_abq"
)
pipeline.run(abq_crime)
```

**Why start here:** no auth, no scraping, no legal ambiguity, well-structured, and
generously sized. You'll hit every part of the stack (ingest → land → model →
chart) in one afternoon with a source that won't fight you. Get the whole loop
working on ABQ data *before* you touch the harder sources.

Good first datasets: crime incidents, building permits, 311 requests, bus
ridership, city budget/checkbook. The checkbook data is especially fun to join
against legislative data later.

### Source 2: NM legislature

Do **not** scrape `nmlegis.gov` first. Check these in order:

1. **Open States** (`openstates.org`) — nonprofit, covers all 50 state legislatures
   including NM, has a documented API *and* bulk CSV/JSON downloads of bills,
   votes, legislators, and sponsorships. Free tier with a key. This is almost
   certainly the right answer.
2. **LegiScan** — commercial-ish API with a free tier, also covers NM, includes
   bill text.
3. Only if neither works: scrape, politely (see the Playwright section).

Bulk download beats API here — grab the whole session as one file, land it in
RustFS, and re-load on a weekly schedule. Legislative data changes slowly except
during session.

Model it as: `dim_legislator`, `dim_committee`, `fct_bill`, `fct_bill_action`,
`fct_vote`. That's a genuinely interesting star schema and a great dbt exercise.

### Source 3: Your bills (PDFs + spreadsheet)

This is the highest-value dataset for you personally, and the fiddliest. Split it
into three independent pieces so one broken vendor doesn't block the others.

**3a. The spreadsheet — do this first, it takes 20 minutes.**

Your existing tracking spreadsheet is already the ground truth. Land it as-is:

```python
@dlt.resource(name="statements_manual", write_disposition="replace")
def statements_manual():
    # export to CSV in a synced folder, or read the Google Sheet API
    yield from csv.DictReader(open("/data/bills.csv"))
```

Now you have `fct_statement` with vendor, date, amount, due date. You can build the
"what do I spend per month by vendor" dashboard **today**, and every later source
just enriches this table. Don't let PDF parsing block you from having a working
dataset.

**3b. The PDFs — let paperless-ngx do the hard part.**

You already have `apps/base/paperless-ngx/` scaffolded. Deploy it. Paperless does
OCR, full-text indexing, tagging, correspondent detection, and custom fields, and
stores all of it in Postgres. That's ~80% of a document pipeline you'd otherwise
build.

Then your dlt source reads *paperless's Postgres*, not the PDFs:

```python
@dlt.resource(name="paperless_documents", write_disposition="merge", primary_key="id")
def paperless_documents():
    # documents_document joined to correspondents, tags, custom field values
    yield from query(PAPERLESS_DSN, """
        select d.id, d.title, d.created, d.content,
               c.name as correspondent, ...
        from documents_document d
        left join documents_correspondent c on c.id = d.correspondent_id
    """)
```

Set up paperless with a `Utility Bill` document type and custom fields for
`amount_due`, `service_period_start`, `due_date`. Paperless can auto-populate some
of this from regex rules per correspondent; the rest you fill in once per document
while you're filing it anyway.

For the ones where you want full extraction, a `pdfplumber` + per-vendor regex
module is more reliable and far cheaper than an LLM — utility bills have stable
layouts. Keep a `parsers/{pnm,gas_company,water_authority}.py` and a test fixture
PDF for each. When a vendor redesigns their bill, one test fails and you know
exactly what to fix.

**3c. Playwright downloads.**

This is fine — they're your own accounts and your own statements. Practical advice:

- Run it as a **Kubernetes CronJob**, not inside Dagster's main container. Use
  `mcr.microsoft.com/playwright/python:v1.x-jammy` so the browsers are preinstalled.
  Give it `~1Gi` RAM; Chromium is hungry, and you're on one node.
- Credentials via ExternalSecret from a 1Password item per vendor
  (`vendor-pnm`, `vendor-comcast`, …) — same pattern as
  [03-secrets.md](03-secrets.md) Tier 2.
- **Persist browser state** (`context.storage_state()`) to a PVC so you're not
  re-authenticating (and re-triggering MFA) every run.
- Expect MFA to break this on some vendors. Design for partial success: the job
  writes what it can to `s3://lake/raw/statements/<vendor>/<yyyy-mm>/`, logs the
  failures, and **notifies you via ntfy** (already deployed) so you can grab that
  one manually. A pipeline that handles 6 of 8 vendors automatically and pings you
  about the other 2 is a huge win; one that needs all 8 to work is fragile.
- Run **monthly, staggered, with jitter** — one login per vendor per month is
  indistinguishable from normal use. Don't poll daily.
- Land the raw PDF in S3 *and* push it into paperless via its API, so 3b picks it
  up. That way manual and automated documents flow through the same path.

```yaml
# a sketch — one CronJob per vendor keeps failures isolated
apiVersion: batch/v1
kind: CronJob
metadata:
  name: fetch-statements-pnm
  namespace: data
spec:
  schedule: "0 7 12 * *"          # 12th of the month
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: fetch
              image: ghcr.io/austindsmith/statement-fetcher:1.2.0
              args: ["--vendor", "pnm"]
              envFrom:
                - secretRef: { name: vendor-pnm }
              resources:
                requests: { cpu: 200m, memory: 768Mi }
                limits:   { memory: 1536Mi }
              volumeMounts:
                - { name: state, mountPath: /state }
          volumes:
            - name: state
              persistentVolumeClaim: { claimName: statement-fetcher-state }
```

---

## Part 4: A four-week plan

**Week 1 — make one loop work end to end.**
Create the `lake` bucket in RustFS and `raw`/`staging`/`marts` databases in
ClickHouse. Write one dlt script for one ABQ dataset, run it *from your laptop*
against the cluster. Deploy Metabase, connect it to ClickHouse, build one chart.
Nothing scheduled, nothing orchestrated. **Goal: a chart on a screen made from real
data.** This is the milestone that makes the rest feel worth it.

**Week 2 — add transformation.**
Initialize the dbt project with `dbt-clickhouse`. Build `stg_abq_crime` (typed,
renamed) and one mart. Add three dbt tests. Run `dbt build` locally. **Goal:
`raw → staging → marts` exists and is tested.**

**Week 3 — automate.**
Enable the Dagster HelmRelease, point it at `data-cluster` Postgres, containerize
the data repo. Wrap the dlt script and the dbt project as Dagster assets. Schedule
daily. **Goal: you stop running things by hand.**

**Week 4 — your own data.**
Land the bills spreadsheet. Deploy paperless-ngx. Write the first Playwright
CronJob for whichever vendor has the simplest login. **Goal: a spend-by-vendor
dashboard.**

Then add sources one at a time. Each new source should be one dlt resource, one
staging model, and one line in the Dagster schedule — if it's more than that, the
platform isn't finished, and you should fix the platform rather than work around it.

---

## Part 5: Conventions worth setting now

**Landing zone layout** — immutable, partitioned, self-describing:

```
s3://lake/raw/<source>/<dataset>/ingest_date=2026-08-12/part-0001.parquet
s3://lake/raw/statements/pnm/2026-07/statement.pdf
```

Never overwrite. Never edit. If a transform is wrong, you re-run it from raw. This
one rule saves you more grief than any tool.

**ClickHouse table naming:**

| Layer | Prefix | Example | Owner |
| --- | --- | --- | --- |
| Raw | `raw_` | `raw.raw_abq_crime` | dlt |
| Staging | `stg_` | `staging.stg_abq_crime` | dbt |
| Dimension | `dim_` | `marts.dim_legislator` | dbt |
| Fact | `fct_` | `marts.fct_statement` | dbt |

**Every raw table gets:** `_loaded_at` (timestamp), `_source` (string),
`_source_file` (string). When a number looks wrong six months from now, these three
columns are how you find out why.

**ClickHouse specifics:** use `ReplacingMergeTree` with a version column for
mergeable sources, `ORDER BY` the columns you actually filter on (usually a date
and an id), and partition by month — not by day, you'll create too many parts on a
small node.

**Write down what each dataset is.** A `sources.yml` in dbt with a `description` on
every source and column costs two minutes per table and is the difference between a
lakehouse and a pile of tables. Dagster surfaces these descriptions in its asset
graph, so it doubles as your catalog — which is why you don't need DataHub.

---

## The one-line version

Delete 90% of `data-lakehouse/`, run **RustFS + ClickHouse + Postgres + dlt + dbt +
Dagster + Metabase**, land raw files immutably in S3, and get one ABQ dataset all
the way to a chart before you touch anything else.
