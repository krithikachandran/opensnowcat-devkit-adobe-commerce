# OpenSnowcat Pipeline Configuration

This directory contains all configuration for the core pipeline components: collector, enricher, and Iglu schema registry.

## Files

| File | Component | Purpose |
|------|-----------|---------|
| `config.collector.hocon` | Collector | HTTP endpoint config, Kafka producer settings |
| `config.enrich.hocon` | Enricher | Kafka consumer/producer settings, monitoring |
| `resolver.json` | Schema Resolver | Iglu registry endpoints (local server + Iglu Central) |
| `iglu-server.hocon` | Iglu Server | Local schema registry config (Postgres backend) |
| `enrichments/*.json` | Enricher | Individual enrichment plugin configurations |

## Schema Resolution

The enricher validates events against schemas using `resolver.json`. Repositories are checked in priority order:

1. **Local Iglu Server** (priority 1) — custom schemas at `http://iglu-server:8080`
2. **Iglu Central** (priority 10) — standard Snowplow schemas
3. **Iglu Central GCP Mirror** (priority 20) — fallback mirror

## Enrichments

Enrichment plugins are configured in `enrichments/`. The enricher loads all `.json` files from that directory at startup; toggle individual enrichments with the `enabled` field.

All BDP-active enrichments are turned on for parity. The one exception is **IAB**, which is blocked on licensed list files — see `enrichments/NOTES.md` for details.

| Enrichment | State | BDP | What it does |
|-----------|-------|-----|-------------|
| `campaign_attribution_enrichment_config.json` | on | ✅ | Extracts UTM parameters |
| `yauaa_enrichment_config.json` | on | ✅ | Parses User-Agent (device/OS/browser) — preferred over ua-parser |
| `ua_parser_enrichment_config.json` | on | ✅ | Parses User-Agent via uap-core (runs alongside YAUAA for BDP column parity) |
| `referer_parser_enrichment_config.json` | on | ✅ | Identifies traffic source from referrer |
| `event_fingerprint_enrichment.json` | on | ✅ | MD5 hash for deduplication |
| `anon_ip_enrichment_config.json` | on | ✅ | Masks IP address octets |
| `pseudonymization_enrichment.json` | on | ✅ | SHA-256 hash of user_id |
| `ip_lookups_enrichment_config.json` | on | ✅ | MaxMind GeoIP lookup — **requires a free MaxMind account** for the GeoLite2 download (see below) |
| `iab_spiders_and_robots_enrichment.json` | **off** | ✅ | IAB/ABC bot detection — blocked on licensed list files, see `enrichments/NOTES.md` |
| `http_header_extractor_config.json` | on | ❌ | Extracts HTTP headers — not in BDP; kept on for Shopify webhook support |

### Enrichment data files

Some enrichments need external data files. Place them under `enrichments-data/` (mounted into the enricher at `/opensnowcat/enrichments-data/`):

```
opensnowcat/enrichments-data/
├── maxmind/    GeoLite2-City.mmdb        ← free, requires MaxMind account
├── uap/        regexes.yaml              ← free, fetched from ua-parser/uap-core
└── iab/        ip_exclude_current_cidr.txt, exclude_current.txt, include_current.txt
                                          ← licensed, obtained from IAB Tech Lab
```

Fetch them with:

```bash
make fetch-enrichment-data
```

This always downloads `regexes.yaml` from uap-core (no auth). It only downloads the MaxMind `GeoLite2-City.mmdb` if `MAXMIND_LICENSE_KEY` is set in `.env` — otherwise it prints a warning and skips. The enricher will refuse to start with `ip_lookups` enabled and no `.mmdb` present, so the MaxMind step is required to run the pipeline end-to-end.

### MaxMind setup (required for IP lookup)

GeoLite2 is free but gated behind a MaxMind account:

1. Sign up at [maxmind.com/en/geolite2/signup](https://www.maxmind.com/en/geolite2/signup) (no credit card)
2. *My Account → Manage License Keys → Generate new license key* — answer **No** when asked whether you'll use it with GeoIP Update
3. Add the key to `.env`:
   ```
   MAXMIND_LICENSE_KEY=<your-key>
   ```
4. `make fetch-enrichment-data` — should now log `Fetching GeoLite2-City...` and produce `enrichments-data/maxmind/GeoLite2-City.mmdb`
5. `docker compose restart opensnowcat_enrich`

The `.mmdb` file expires after ~30 days of staleness from MaxMind's perspective; re-running `make fetch-enrichment-data` periodically refreshes it (a weekly cron in production is typical).

### IAB (paid)

IAB data is licensed from [IAB Tech Lab](https://iabtechlab.com/software/iab-abc-international-spiders-bots-list/) — see `enrichments/NOTES.md` for the current blocker and workarounds. If you don't license it, YAUAA's `agentClass=Robot` field is a weaker substitute.

## Local Iglu Server

The Iglu Server runs on port 8181 (host) and provides a REST API for managing schemas.

- Health check: `curl http://localhost:8181/api/meta/health`
- List schemas: `curl http://localhost:8181/api/schemas`
- Upload schema: `curl -X POST http://localhost:8181/api/schemas -H "apikey: YOUR_KEY" -H "Content-Type: application/json" -d @schema.json`

The super API key is set via `IGLU_SUPER_API_KEY` in `.env`.

## GCP Configuration

See `gcp/README.md` for Google Cloud Pub/Sub deployment configs.
