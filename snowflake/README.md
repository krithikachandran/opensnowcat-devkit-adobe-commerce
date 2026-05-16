# Snowflake Streaming Loader

Loads enriched events from Kafka into `SNOWPLOW_QA.WEB.ATOMIC_EVENTS` using the **Snowplow Snowflake Streaming Loader** (Snowpipe Streaming API).

## What this is

The official Snowplow loader image `snowplow/snowflake-loader-kafka` consumes the enricher's `enriched-good` TSV topic directly and writes via Snowpipe Streaming. No warehouse compute, sub-second latency, key-pair auth.

```
enriched-good (Kafka TSV) → snowflake-loader → Snowpipe Streaming → SNOWPLOW_QA.WEB.ATOMIC_EVENTS
```

Bad events (`collected-bad`, `enriched-bad`) stay in Kafka for debugging — they're never loaded.

## Prerequisites

1. A Snowflake account with `SNOWPLOW_QA` database and `WEB` schema
2. The `atomic_events` table created (see step 1 below)
3. A loader user (e.g. `DS_QA_ML_SERVICE`) with key-pair auth registered
4. A loader role (e.g. `DS_QA_ML_READ_ROLE`) granted on the table

## Setup

### 1. Create the table

Run `snowflake/atomic_events.sql` against `SNOWPLOW_QA.WEB`:

```bash
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER -d SNOWPLOW_QA -s WEB -f snowflake/atomic_events.sql
```

The Streaming Loader can auto-create the table on first run, but we ship the explicit DDL to keep column types/precision deterministic and aligned with the BDP `atomic.events` table.

### 2. Grant permissions

Run `snowflake/grants.sql` as `ACCOUNTADMIN`:

```sql
GRANT USAGE ON DATABASE SNOWPLOW_QA TO ROLE DS_QA_ML_READ_ROLE;
GRANT USAGE ON SCHEMA SNOWPLOW_QA.WEB TO ROLE DS_QA_ML_READ_ROLE;
GRANT INSERT, SELECT ON TABLE SNOWPLOW_QA.WEB.ATOMIC_EVENTS TO ROLE DS_QA_ML_READ_ROLE;
```

No warehouse grants required — Snowpipe Streaming bypasses the warehouse.

### 3. Generate the key pair

```bash
make snowflake-keypair
```

This generates:
- `snowflake/snowflake-key.p8` — private key (gitignored, used by the loader)
- `snowflake/snowflake-key.pub` — public key

The script prints an `ALTER USER` statement. Run it in Snowflake:

```sql
ALTER USER DS_QA_ML_SERVICE SET RSA_PUBLIC_KEY = '<base64 contents from script>';
```

Verify:
```sql
DESC USER DS_QA_ML_SERVICE;  -- RSA_PUBLIC_KEY_FP should be populated
```

### 4. Configure credentials

Set in `.env`:
```
SNOWFLAKE_ACCOUNT=adobemagento.us-east-1
SNOWFLAKE_USER=DS_QA_ML_SERVICE
SNOWFLAKE_DATABASE=SNOWPLOW_QA
SNOWFLAKE_SCHEMA=WEB
SNOWFLAKE_ROLE=DS_QA_ML_READ_ROLE
SNOWFLAKE_PRIVATE_KEY_PATH=./snowflake/snowflake-key.p8
SNOWFLAKE_PRIVATE_KEY_PASSPHRASE=        # empty for unencrypted key
```

### 5. Start the loader

```bash
docker compose up -d snowflake-loader
docker compose logs -f snowflake-loader
```

## Configuration

The loader is configured in `opensnowcat/snowflake-streaming-loader.hocon`. Key knobs:

| Field | Default | Effect |
|---|---|---|
| `batching.maxBytes` | 16000000 (16 MB) | Flush when batch exceeds this size |
| `batching.maxDelay` | `1 second` | Max time to wait before flushing a partial batch |
| `input.consumerConf.group.id` | `snowplow-snowflake-streaming-loader` | Kafka consumer group; offset is tracked here |

Lowering `maxDelay` reduces latency at higher Snowflake cost; raising it increases throughput per write.

## Data Flow vs. BDP

BDP uses the RDB Loader (batch COPY from S3, ~5–10 min latency). This devkit uses the Streaming Loader (Snowpipe Streaming, ~1s latency). Both write to the same canonical `atomic.events` table shape, so downstream models (dbt etc.) work identically.

## Table Schema

`atomic_events.sql` matches the BDP `SNOWPLOW.ATOMIC.EVENTS` table exactly: 128 canonical fields + flattened `contexts_*` (`ARRAY`) and `unstruct_event_*` (`OBJECT`) columns + `LOAD_TSTAMP`. The Streaming Loader will `ALTER TABLE ADD COLUMN` automatically when it sees a new context/unstruct schema, so new schemas don't require a manual migration.
