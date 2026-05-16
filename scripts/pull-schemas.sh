#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${ROOT_DIR}/.env"
SCHEMAS_DIR="${ROOT_DIR}/schemas"

if [ ! -f "$ENV_FILE" ]; then
  echo "Error: .env file not found at ${ENV_FILE}"
  echo "Copy .env.example to .env and fill in your Snowplow credentials."
  exit 1
fi

source "$ENV_FILE"

for var in SNOWPLOW_CONSOLE_ORG_ID SNOWPLOW_CONSOLE_API_KEY_ID SNOWPLOW_CONSOLE_API_KEY; do
  if [ -z "${!var:-}" ] || [ "${!var}" = "your-org-id" ] || [ "${!var}" = "your-api-key-id" ] || [ "${!var}" = "your-api-key" ]; then
    echo "Error: ${var} is not set in .env"
    exit 1
  fi
done

BASE_URL="https://console.snowplowanalytics.com/api/msc/v1/organizations/${SNOWPLOW_CONSOLE_ORG_ID}"

echo "Authenticating with Snowplow Console..."
TOKEN=$(curl -sf "${BASE_URL}/credentials/v3/token" \
  -H "X-API-Key-ID: ${SNOWPLOW_CONSOLE_API_KEY_ID}" \
  -H "X-API-Key: ${SNOWPLOW_CONSOLE_API_KEY}" | python3 -c "import sys,json; print(json.load(sys.stdin)['accessToken'])")

echo "Fetching data structures..."
STRUCTURES=$(curl -sf "${BASE_URL}/data-structures/v1" \
  -H "authorization: Bearer ${TOKEN}")

COUNT=$(echo "$STRUCTURES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
echo "Found ${COUNT} data structures"
echo "Fetching all versions for each structure..."

mkdir -p "$SCHEMAS_DIR"

echo "$STRUCTURES" | python3 -c "
import sys, json, os, urllib.request, time

structures = json.load(sys.stdin)
schemas_dir = '${SCHEMAS_DIR}'
base_url = '${BASE_URL}'
token = '${TOKEN}'

total = 0
errors = 0

for s in structures:
    vendor = s['vendor']
    name = s['name']
    fmt = s['format']
    hash_id = s['hash']

    # Collect all unique versions from deployments
    all_versions = set()
    for d in s.get('deployments', []):
        all_versions.add(d['version'])

    if not all_versions:
        print(f'  SKIP {vendor}/{name} (no deployments)')
        continue

    # Parse and sort versions numerically (1-0-0 < 1-0-1 < 2-0-0)
    def version_key(v):
        parts = v.split('-')
        return tuple(int(p) for p in parts)

    sorted_versions = sorted(all_versions, key=version_key)
    latest = sorted_versions[-1]
    major, minor, patch = version_key(latest)

    # Generate all versions from 1-0-0 up to the latest
    # We need to fill gaps so Iglu Server accepts them in order
    versions_to_fetch = set()
    for m in range(1, major + 1):
        versions_to_fetch.add(f'{m}-0-0')
    # Add all intermediate versions we know about
    versions_to_fetch.update(sorted_versions)
    # For the latest major, add versions up to latest
    for p in range(0, patch + 1):
        versions_to_fetch.add(f'{major}-{minor}-{p}')
    # For minor bumps in latest major
    for mi in range(0, minor + 1):
        versions_to_fetch.add(f'{major}-{mi}-0')

    versions_to_fetch = sorted(versions_to_fetch, key=version_key)

    for version in versions_to_fetch:
        url = f'{base_url}/data-structures/v1/{hash_id}/versions/{version}'
        req = urllib.request.Request(url, headers={'authorization': f'Bearer {token}'})
        try:
            with urllib.request.urlopen(req) as resp:
                version_data = json.loads(resp.read())
            schema_body = version_data.get('data', version_data)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                # Version doesn't exist in BDP, use the nearest version we have as a stub
                # Find the closest prior version that exists on disk
                schema_dir = os.path.join(schemas_dir, vendor, name, fmt)
                existing = []
                if os.path.exists(schema_dir):
                    existing = sorted(os.listdir(schema_dir), key=version_key)
                if existing:
                    stub_path = os.path.join(schema_dir, existing[-1])
                    with open(stub_path, 'r') as f:
                        schema_body = json.load(f)
                    print(f'  STUB {vendor}/{name}/{fmt}/{version} (from {existing[-1]})')
                else:
                    print(f'  SKIP {vendor}/{name}/{fmt}/{version} (404, no stub)')
                    continue
            else:
                print(f'  ERROR {vendor}/{name}/{fmt}/{version}: HTTP {e.code}')
                errors += 1
                continue

        schema_dir = os.path.join(schemas_dir, vendor, name, fmt)
        os.makedirs(schema_dir, exist_ok=True)
        schema_path = os.path.join(schema_dir, version)
        with open(schema_path, 'w') as f:
            json.dump(schema_body, f, indent=2)
        total += 1

    print(f'  OK {vendor}/{name}/{fmt} ({len(versions_to_fetch)} versions)')

print(f'')
print(f'Saved {total} schema versions to {schemas_dir}')
if errors:
    print(f'{errors} errors occurred')
"

echo ""
echo "Done. Schemas saved to schemas/"
echo "Run 'make upload-schemas' to push them to the local Iglu Server."
