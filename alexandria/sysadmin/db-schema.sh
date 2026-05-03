#!/bin/bash -i

if [ ! -f .env ]; then
  echo "=> No .env file found"
  exit 1
fi

set -o allexport
source .env
set +o allexport

required_vars=( "ALEXANDRIA_LOCAL_PORT" "SERVER_USER_AT_IP" "SERVER_PORT" "ALEXANDRIA_DB_CONTAINER" "ALEXANDRIA_DB_USER" "ALEXANDRIA_DB_NAME" )

var_err_msg=
for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    var_err_msg="${var_err_msg}=> Error: Missing required environment variable: $var\n"
  fi
done

if [ -n "$var_err_msg" ]; then
  echo -e "$var_err_msg"
  echo "=> Please make sure the required environment variables are set in .env. Exiting."
  exit 1
fi

# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

run_psql() {
  local sql="$1"
  if pgrep -fa "ssh" 2>/dev/null | grep -qE "\b${ALEXANDRIA_LOCAL_PORT}:localhost"; then
    echo "$sql" | ssh -p "${SERVER_PORT}" "${SERVER_USER_AT_IP}" \
      "docker exec -i ${ALEXANDRIA_DB_CONTAINER} psql -U ${ALEXANDRIA_DB_USER} -d ${ALEXANDRIA_DB_NAME}"
  else
    echo "$sql" | docker exec -i "${ALEXANDRIA_DB_CONTAINER}" \
      psql -U "${ALEXANDRIA_DB_USER}" -d "${ALEXANDRIA_DB_NAME}"
  fi
}

# MAIN

print_target_banner "${ALEXANDRIA_LOCAL_PORT}"
echo "=> Dumping DB schema..."

SQL="
\echo ''
\echo '=== Tables and Row Counts ==='
SELECT
    t.table_name,
    COALESCE(s.n_live_tup, 0) AS rows
FROM information_schema.tables t
LEFT JOIN pg_stat_user_tables s ON s.relname = t.table_name
WHERE t.table_schema = 'public'
  AND t.table_type = 'BASE TABLE'
ORDER BY t.table_name;

\echo ''
\echo '=== Columns ==='
SELECT
    table_name,
    column_name,
    CASE
        WHEN character_maximum_length IS NOT NULL THEN data_type || '(' || character_maximum_length || ')'
        WHEN numeric_precision IS NOT NULL AND data_type = 'numeric'
            THEN data_type || '(' || numeric_precision || ',' || COALESCE(numeric_scale, 0) || ')'
        ELSE data_type
    END AS type,
    is_nullable AS nullable
FROM information_schema.columns
WHERE table_schema = 'public'
ORDER BY table_name, ordinal_position;
"

run_psql "$SQL"
