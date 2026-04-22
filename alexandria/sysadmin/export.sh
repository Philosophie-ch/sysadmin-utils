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

valid_entities=( authors journals publishers institutions schools series keywords bibitems )

if [ -z "$1" ]; then
  echo "=> Usage: $0 <entity> [output-file.csv]"
  echo "=> Valid entities: ${valid_entities[*]}"
  exit 1
fi

entity="$1"
output_file="${2:-${entity}_$(date +%Y%m%d_%H%M%S).csv}"

valid=0
for e in "${valid_entities[@]}"; do
  [ "$entity" = "$e" ] && valid=1 && break
done

if [ "$valid" -eq 0 ]; then
  echo "=> Unknown entity: $entity"
  echo "=> Valid entities: ${valid_entities[*]}"
  exit 1
fi

# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

# MAIN

print_target_banner "${ALEXANDRIA_LOCAL_PORT}"
echo "=> Exporting $entity to $output_file..."
curl -sf -X POST \
  -H "Authorization: Bearer ${ALEXANDRIA_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{}' \
  "http://localhost:${ALEXANDRIA_LOCAL_PORT}/api/v1/admin/export/${entity}" \
  > "$output_file" || { echo "=> Export failed or tunnel is not open"; exit 1; }

echo "=> Done: $output_file"
