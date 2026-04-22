#!/bin/bash -i

if [ ! -f .env ]; then
  echo "=> No .env file found"
  exit 1
fi

set -o allexport
source .env
set +o allexport

required_vars=( "SERVER_USER_AT_IP" "SERVER_PORT" "ALEXANDRIA_API_KEY" "ALEXANDRIA_LOCAL_PORT" )

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

if [ -z "$1" ]; then
  echo "=> Usage: $0 <file.csv>"
  exit 1
fi

csv_file="$1"

if [ ! -f "$csv_file" ]; then
  echo "=> File not found: $csv_file"
  exit 1
fi

# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

# MAIN

print_target_banner "${ALEXANDRIA_LOCAL_PORT}"
echo "=> Validating CSV: $csv_file"
curl -sf -X POST \
  -H "Authorization: Bearer ${ALEXANDRIA_API_KEY}" \
  -F "file=@${csv_file}" \
  "http://localhost:${ALEXANDRIA_LOCAL_PORT}/api/v1/admin/validate-full-csv" \
  | jq . || echo "=> Validation failed or tunnel is not open"
