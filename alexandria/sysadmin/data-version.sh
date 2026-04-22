#!/bin/bash -i

if [ ! -f .env ]; then
  echo "=> No .env file found"
  exit 1
fi

set -o allexport
source .env
set +o allexport

required_vars=( "ALEXANDRIA_LOCAL_PORT" )

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

# MAIN

print_target_banner "${ALEXANDRIA_LOCAL_PORT}"
echo "=> Fetching Alexandria data version..."
curl -sf "http://localhost:${ALEXANDRIA_LOCAL_PORT}/api/v1/data-version" | python3 -m json.tool || echo "=> Alexandria is not reachable"
