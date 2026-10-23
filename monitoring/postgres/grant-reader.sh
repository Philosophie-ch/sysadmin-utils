#!/usr/bin/env bash
# Creates or updates the read-only "grafana_reader" role in one application database
# and grants it SELECT on every column of the public schema except secrets.
# Re-run after schema changes: grants are revoked and recomputed from the live schema,
# so new tables and columns stay invisible until then.
#
# Usage (on the monitoring host): bash postgres/grant-reader.sh portal|alexandria
# Reads <APP>_DB_CONTAINER, <APP>_DB_NAME, <APP>_DB_OWNER, <APP>_DB_READER_PASSWORD from ../.env
# (or from ENV_FILE when set)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="${1:?usage: $0 portal|alexandria}"
PREFIX="$(echo "$APP" | tr '[:lower:]' '[:upper:]')"

set -a
# shellcheck disable=SC1090
. "${ENV_FILE:-${SCRIPT_DIR}/../.env}"
set +a

CONTAINER_VAR="${PREFIX}_DB_CONTAINER"; NAME_VAR="${PREFIX}_DB_NAME"
OWNER_VAR="${PREFIX}_DB_OWNER"; PASSWORD_VAR="${PREFIX}_DB_READER_PASSWORD"
CONTAINER="${!CONTAINER_VAR:?set ${CONTAINER_VAR} in .env}"
DB="${!NAME_VAR:?set ${NAME_VAR} in .env}"
OWNER="${!OWNER_VAR:?set ${OWNER_VAR} in .env}"
PASSWORD="${!PASSWORD_VAR:?set ${PASSWORD_VAR} in .env}"

# Keeps the password safe to embed in SQL; generate one with: openssl rand -hex 24
if [[ ! "$PASSWORD" =~ ^[A-Za-z0-9]{24,}$ ]]; then
    echo "Error: ${PASSWORD_VAR} must be at least 24 letters or digits" >&2
    exit 1
fi

# Column names never granted; matched case-insensitively against the whole name
SECRET_COLUMNS='token|password|salt|digest|secret|unlock|encrypted|api_key|key_hash'

echo "Granting grafana_reader on ${DB} (${CONTAINER})..."

# SQL goes in on stdin so the password never appears in a process list
docker exec -i "$CONTAINER" psql -U "$OWNER" -d "$DB" -v ON_ERROR_STOP=1 -q <<SQL
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'grafana_reader') THEN
    CREATE ROLE grafana_reader;
  END IF;
END \$\$;

ALTER ROLE grafana_reader WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT
  NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 5 PASSWORD '${PASSWORD}';
ALTER ROLE grafana_reader SET default_transaction_read_only = on;
ALTER ROLE grafana_reader SET statement_timeout = '30s';
ALTER ROLE grafana_reader SET idle_in_transaction_session_timeout = '60s';

BEGIN;

-- Start from nothing; column grants are not removed by table-level REVOKE
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM grafana_reader;
DO \$\$
DECLARE r record;
BEGIN
  FOR r IN SELECT DISTINCT table_name, column_name FROM information_schema.column_privileges
           WHERE grantee = 'grafana_reader' AND table_schema = 'public'
  LOOP
    EXECUTE format('REVOKE ALL (%I) ON public.%I FROM grafana_reader', r.column_name, r.table_name);
  END LOOP;
END \$\$;

GRANT CONNECT ON DATABASE "${DB}" TO grafana_reader;
GRANT USAGE ON SCHEMA public TO grafana_reader;

DO \$\$
DECLARE r record;
BEGIN
  FOR r IN SELECT c.table_name, string_agg(format('%I', c.column_name), ', ' ORDER BY c.ordinal_position) AS cols
           FROM information_schema.columns c
           JOIN information_schema.tables t USING (table_schema, table_name)
           WHERE c.table_schema = 'public' AND t.table_type IN ('BASE TABLE', 'VIEW')
             AND c.column_name !~* '${SECRET_COLUMNS}'
           GROUP BY c.table_name
  LOOP
    EXECUTE format('GRANT SELECT (%s) ON public.%I TO grafana_reader', r.cols, r.table_name);
  END LOOP;
END \$\$;

COMMIT;

\pset tuples_only on
\pset format unaligned
SELECT format('%s tables, %s columns granted; %s columns withheld: %s',
  count(DISTINCT p.table_name), count(*),
  (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND column_name ~* '${SECRET_COLUMNS}'),
  (SELECT string_agg(table_name || '.' || column_name, ', ' ORDER BY table_name, column_name)
     FROM information_schema.columns WHERE table_schema = 'public' AND column_name ~* '${SECRET_COLUMNS}'))
FROM information_schema.column_privileges p
WHERE p.grantee = 'grafana_reader' AND p.table_schema = 'public' AND p.privilege_type = 'SELECT';
SQL
