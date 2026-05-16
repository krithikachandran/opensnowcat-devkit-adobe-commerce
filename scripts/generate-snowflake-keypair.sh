#!/usr/bin/env bash
# Generates an RSA key pair for Snowflake Snowpipe Streaming auth and prints
# a complete Snowflake setup SQL block: CREATE USER (key-pair only, no
# password), CREATE ROLE, GRANT statements, and the ALTER USER ... SET
# RSA_PUBLIC_KEY statement with the generated public key inlined.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_DIR="${REPO_ROOT}/snowflake"
PRIVATE_KEY="${KEY_DIR}/snowflake-key.p8"
PUBLIC_KEY="${KEY_DIR}/snowflake-key.pub"

# Defaults — override via env if you want different names
SF_USER="${SNOWFLAKE_LOADER_USER:-DS_OPENSNOWCAT_SNOWFLAKE_LOADER}"
SF_ROLE="${SNOWFLAKE_LOADER_ROLE:-DS_OPENSNOWCAT_SNOWFLAKE_LOADER_ROLE}"
SF_DATABASE="${SNOWFLAKE_DATABASE:-SNOWPLOW_QA}"
SF_SCHEMA="${SNOWFLAKE_SCHEMA:-WEB}"
SF_TABLE="${SNOWFLAKE_TABLE:-ATOMIC_EVENTS}"

mkdir -p "$KEY_DIR"

if [[ -f "$PRIVATE_KEY" ]]; then
  echo "ERROR: $PRIVATE_KEY already exists. Delete it first if you want to regenerate." >&2
  exit 1
fi

echo "Generating unencrypted RSA private key (PKCS#8)..."
openssl genrsa 2048 2>/dev/null \
  | openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt -out "$PRIVATE_KEY"
chmod 600 "$PRIVATE_KEY"

echo "Deriving public key..."
openssl rsa -in "$PRIVATE_KEY" -pubout -out "$PUBLIC_KEY" 2>/dev/null

# Strip PEM headers and newlines for the ALTER USER statement
PUBKEY_BODY="$(awk 'NR>1 && !/-----END/ {printf "%s", $0}' "$PUBLIC_KEY")"

cat <<EOF

✅ Key pair generated:
   Private key: $PRIVATE_KEY  (gitignored, used by the loader)
   Public key:  $PUBLIC_KEY

Run the following SQL in Snowflake (as ACCOUNTADMIN or equivalent):

──────────────────────────────────────────────────────────────────────────
-- 1. Create the dedicated loader role
CREATE ROLE IF NOT EXISTS ${SF_ROLE};

-- 2. Create the dedicated loader user (no password — key-pair auth only)
CREATE USER IF NOT EXISTS ${SF_USER}
  DEFAULT_ROLE = ${SF_ROLE}
  DEFAULT_NAMESPACE = ${SF_DATABASE}.${SF_SCHEMA}
  COMMENT = 'OpenSnowcat devkit Snowflake Streaming Loader user';

-- 3. Grant the role to the user
GRANT ROLE ${SF_ROLE} TO USER ${SF_USER};

-- 4. Register the public key on the user
ALTER USER ${SF_USER} SET RSA_PUBLIC_KEY = '${PUBKEY_BODY}';

-- 5. Grant the role what it needs to load events
--    (no warehouse needed — Snowpipe Streaming bypasses the warehouse)
GRANT USAGE ON DATABASE ${SF_DATABASE} TO ROLE ${SF_ROLE};
GRANT USAGE ON SCHEMA ${SF_DATABASE}.${SF_SCHEMA} TO ROLE ${SF_ROLE};
GRANT INSERT, SELECT ON TABLE ${SF_DATABASE}.${SF_SCHEMA}.${SF_TABLE} TO ROLE ${SF_ROLE};

-- 6. Verify
DESC USER ${SF_USER};  -- RSA_PUBLIC_KEY_FP should be populated
──────────────────────────────────────────────────────────────────────────

After running the SQL:

  1. Confirm your .env contains:
       SNOWFLAKE_USER=${SF_USER}
       SNOWFLAKE_ROLE=${SF_ROLE}
       SNOWFLAKE_PRIVATE_KEY_PATH=./snowflake/snowflake-key.p8

  2. Start the loader:
       docker compose up -d snowflake-loader
       docker compose logs -f snowflake-loader

EOF
