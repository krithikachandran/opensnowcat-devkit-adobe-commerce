# Enrichment notes

The enricher loads every `*.json` file in this directory at startup. Each config has
an `enabled` flag — set it to `false` to keep the file present (as a template) without
activating the enrichment.

This file documents enrichment-specific gotchas — why certain enrichments are
disabled, and what external accounts/credentials are needed to run the enabled
ones.

## Enabled but needs external account: IP lookups

**File:** `ip_lookups_enrichment_config.json`
**Status:** `enabled: true`
**Blocker:** requires a free MaxMind account to download `GeoLite2-City.mmdb`.

Without the `.mmdb` file at `opensnowcat/enrichments-data/maxmind/`, the enricher
will refuse to start. To set up:

1. Sign up at [maxmind.com/en/geolite2/signup](https://www.maxmind.com/en/geolite2/signup)
2. Generate a license key (*My Account → Manage License Keys*)
3. Add `MAXMIND_LICENSE_KEY=<key>` to `.env`
4. Run `make fetch-enrichment-data`

If you don't want to set this up yet, flip `enabled: false` in the config to skip
the enrichment — note that you'll lose all `geo_*` columns (country, region, city,
lat/lon, timezone) in atomic events.

## Disabled: IAB Spiders & Robots

**File:** `iab_spiders_and_robots_enrichment.json`
**Status:** `enabled: false`
**BDP parity:** ❌ blocked

The IAB enrichment requires three licensed list files distributed by IAB Tech Lab:

- `ip_exclude_current_cidr.txt`
- `exclude_current.txt`
- `include_current.txt`

Snowplow normally hosts these for BDP customers under
`s3://snowplow-hosted-assets-proprietary-us-east-1/third-party/com.iab`, but our AWS
account does not have read access to that bucket. The config currently points at a
local path (`file:///opensnowcat/enrichments-data/iab`) — drop the three files into
`opensnowcat/enrichments-data/iab/` and flip `enabled: true` to activate it.

**To unblock**, one of:

1. Ask Snowplow account team for an IAM key scoped to the proprietary assets bucket
   prefix, then swap the three `uri` fields back to the `s3://...` form and add the
   AWS creds to `.env` (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`).
2. License the IAB/ABC list directly from IAB Tech Lab and place the files locally.

Until then, YAUAA's `agentClass` field (`Robot`/`Crawler`/`Hacker`) is a partial
substitute — it catches bots that self-identify in the User-Agent but misses
IP-based detection.
