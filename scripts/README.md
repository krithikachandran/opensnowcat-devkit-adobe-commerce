# Scripts

Automation scripts for the OpenSnowcat devkit.

## pull-schemas.sh

Pulls all custom iglu schemas from Snowplow BDP's Data Structures API and saves them locally.

**Required env vars** (in `.env`):
- `SNOWPLOW_CONSOLE_ORG_ID`
- `SNOWPLOW_CONSOLE_API_KEY_ID`
- `SNOWPLOW_CONSOLE_API_KEY`

**What it does:**
1. Authenticates with Snowplow Console (JWT token exchange)
2. Lists all data structures in the organization
3. Fetches all versions for each structure (Iglu Server requires sequential versions)
4. Saves schemas to `schemas/` in iglu-compatible layout

**Usage:**
```bash
make pull-schemas
# or directly:
./scripts/pull-schemas.sh
```
