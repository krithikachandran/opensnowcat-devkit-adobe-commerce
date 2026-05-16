-- Snowflake setup for the OpenSnowcat Snowflake Streaming Loader.
-- This SQL is also printed by `make snowflake-keypair` with the freshly-
-- generated public key inlined into the ALTER USER statement. Run as
-- ACCOUNTADMIN or a role with USERADMIN + SECURITYADMIN privileges.

-- 1. Dedicated loader role
CREATE ROLE IF NOT EXISTS DS_OPENSNOWCAT_SNOWFLAKE_LOADER_ROLE;

-- 2. Dedicated loader user (key-pair auth only, no password)
CREATE USER IF NOT EXISTS DS_OPENSNOWCAT_SNOWFLAKE_LOADER
  DEFAULT_ROLE = DS_OPENSNOWCAT_SNOWFLAKE_LOADER_ROLE
  DEFAULT_NAMESPACE = SNOWPLOW_QA.WEB
  COMMENT = 'OpenSnowcat devkit Snowflake Streaming Loader user';

GRANT ROLE DS_OPENSNOWCAT_SNOWFLAKE_LOADER_ROLE TO USER DS_OPENSNOWCAT_SNOWFLAKE_LOADER;

-- 3. Register the public key on the user.
--    `make snowflake-keypair` prints the full ALTER USER statement with the
--    public key inlined.
-- ALTER USER DS_OPENSNOWCAT_SNOWFLAKE_LOADER SET RSA_PUBLIC_KEY = '<base64 contents>';

-- 4. Grants for loading. Snowpipe Streaming does NOT use a virtual warehouse,
--    so no warehouse grants are needed.
GRANT USAGE ON DATABASE SNOWPLOW_QA TO ROLE DS_OPENSNOWCAT_SNOWFLAKE_LOADER_ROLE;
GRANT USAGE ON SCHEMA SNOWPLOW_QA.WEB TO ROLE DS_OPENSNOWCAT_SNOWFLAKE_LOADER_ROLE;
GRANT INSERT, SELECT ON TABLE SNOWPLOW_QA.WEB.ATOMIC_EVENTS TO ROLE DS_OPENSNOWCAT_SNOWFLAKE_LOADER_ROLE;

-- 5. (Optional) Allow the loader to auto-add columns when new context /
--    unstruct schemas appear. Snowflake has no granular ALTER TABLE privilege,
--    so this requires transferring OWNERSHIP of the table to the loader role.
--    Skip this if you'd rather pre-create columns yourself in atomic_events.sql
--    and treat any unseen schema as a bad event.
-- GRANT OWNERSHIP ON TABLE SNOWPLOW_QA.WEB.ATOMIC_EVENTS
--   TO ROLE DS_OPENSNOWCAT_SNOWFLAKE_LOADER_ROLE COPY CURRENT GRANTS;
