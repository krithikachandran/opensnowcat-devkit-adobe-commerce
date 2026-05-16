#!/usr/bin/env bash
# send-bad-events.sh
#
# Send a mix of intentionally bad events to the local collector so we can
# validate the bad-event flow end-to-end. Each event is crafted to fail at
# a specific stage; after running, inspect the enriched-bad / collected-bad
# topics in Kafka UI (http://localhost:8081) to see the failure rows.
#
# Usage:
#   ./scripts/send-bad-events.sh [COLLECTOR_URL]
#
# Default COLLECTOR_URL is http://localhost:8080.

set -euo pipefail

COLLECTOR_URL="${1:-http://localhost:8080}"
ENDPOINT="${COLLECTOR_URL%/}/com.snowplowanalytics.snowplow/tp2"

command -v curl    >/dev/null || { echo "curl not found";    exit 1; }
command -v uuidgen >/dev/null || { echo "uuidgen not found"; exit 1; }
command -v base64  >/dev/null || { echo "base64 not found";  exit 1; }

now_ms=$(( $(date +%s) * 1000 ))

fresh_eid() { uuidgen | tr 'A-Z' 'a-z'; }

post_event() {
  local label="$1" payload="$2"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$ENDPOINT" \
    -H "Content-Type: application/json" -d "$payload")
  printf "  [%-32s] HTTP %s\n" "$label" "$code"
}

b64() { printf '%s' "$1" | base64 | tr -d '\n'; }

echo "Sending bad events to $ENDPOINT"
echo ""

# ─────────────────────────────────────────────────────────────────────────
# 1. Invalid UUID in eid
#    Expected: enriched-bad / enrichment_failures
#    (collector accepts the payload, enricher rejects when validating eid)
# ─────────────────────────────────────────────────────────────────────────
post_event "invalid-uuid-eid" "$(cat <<EOF
{
  "schema": "iglu:com.snowplowanalytics.snowplow/payload_data/jsonschema/1-0-4",
  "data": [{
    "e": "pv", "url": "http://test/bad-uuid", "p": "web",
    "tv": "bad-events-test", "aid": "bad-events-test",
    "eid": "this-is-not-a-uuid",
    "dtm": "$now_ms", "stm": "$now_ms"
  }]
}
EOF
)"

# ─────────────────────────────────────────────────────────────────────────
# 2. Context references a schema version that doesn't exist
#    Expected: enriched-bad / schema_violations (ResolutionError NotFound)
# ─────────────────────────────────────────────────────────────────────────
CX_NOT_FOUND=$(b64 '{"schema":"iglu:com.snowplowanalytics.snowplow/contexts/jsonschema/1-0-0","data":[{"schema":"iglu:com.adobe.magento.entity/storefront-instance/jsonschema/9-9-9","data":{"environmentId":"x","environment":"X","storeUrl":"http://x","baseCurrencyCode":"USD","storeViewCurrencyCode":"USD"}}]}')
post_event "schema-version-not-found" "$(cat <<EOF
{
  "schema": "iglu:com.snowplowanalytics.snowplow/payload_data/jsonschema/1-0-4",
  "data": [{
    "e": "pv", "url": "http://test/missing-schema", "p": "web",
    "tv": "bad-events-test", "aid": "bad-events-test",
    "eid": "$(fresh_eid)",
    "dtm": "$now_ms", "stm": "$now_ms",
    "cx": "$CX_NOT_FOUND"
  }]
}
EOF
)"

# ─────────────────────────────────────────────────────────────────────────
# 3. Context payload missing required fields (only environmentId set)
#    Expected: enriched-bad / schema_violations (validation failure)
# ─────────────────────────────────────────────────────────────────────────
CX_MISSING_FIELDS=$(b64 '{"schema":"iglu:com.snowplowanalytics.snowplow/contexts/jsonschema/1-0-0","data":[{"schema":"iglu:com.adobe.magento.entity/storefront-instance/jsonschema/3-0-3","data":{"environmentId":"abc"}}]}')
post_event "schema-violation-missing-fields" "$(cat <<EOF
{
  "schema": "iglu:com.snowplowanalytics.snowplow/payload_data/jsonschema/1-0-4",
  "data": [{
    "e": "pv", "url": "http://test/missing-required", "p": "web",
    "tv": "bad-events-test", "aid": "bad-events-test",
    "eid": "$(fresh_eid)",
    "dtm": "$now_ms", "stm": "$now_ms",
    "cx": "$CX_MISSING_FIELDS"
  }]
}
EOF
)"

# ─────────────────────────────────────────────────────────────────────────
# 4. Context payload has wrong field type (shopperId should be string,
#    sending a number)
#    Expected: enriched-bad / schema_violations (type validation failure)
# ─────────────────────────────────────────────────────────────────────────
CX_WRONG_TYPE=$(b64 '{"schema":"iglu:com.snowplowanalytics.snowplow/contexts/jsonschema/1-0-0","data":[{"schema":"iglu:com.adobe.magento.entity/shopper/jsonschema/1-0-0","data":{"shopperId":12345}}]}')
post_event "wrong-field-type" "$(cat <<EOF
{
  "schema": "iglu:com.snowplowanalytics.snowplow/payload_data/jsonschema/1-0-4",
  "data": [{
    "e": "pv", "url": "http://test/wrong-type", "p": "web",
    "tv": "bad-events-test", "aid": "bad-events-test",
    "eid": "$(fresh_eid)",
    "dtm": "$now_ms", "stm": "$now_ms",
    "cx": "$CX_WRONG_TYPE"
  }]
}
EOF
)"

echo ""
echo "Done. 4 bad events sent."
echo ""
echo "Verify in Kafka UI (http://localhost:8081):"
echo "  - enriched-bad should have +4 messages"
echo "  - collected-good should have +4 (collector accepted them)"
echo "  - enriched-good should be unchanged"
echo "  - SNOWPLOW_QA.WEB.ATOMIC_EVENTS should be unchanged"
