#!/bin/bash -i

# Load environment variables
if [ ! -f .env ]; then
  echo "=> No .env file found"
  exit 1
fi

set -o allexport
source .env
set +o allexport

required_vars=( "SERVER_USER_AT_IP" "SERVER_PORT" "ALEXANDRIA_LOCAL_PORT" )

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

# MAIN

local_port="${ALEXANDRIA_LOCAL_PORT}"

if nc -z -w1 localhost "${local_port}" 2>/dev/null; then
  echo "=> Port ${local_port} is already in use."
  read -r -p "=> Enter a different local port to use: " local_port
  if ! [[ "$local_port" =~ ^[0-9]+$ ]] || [ "$local_port" -lt 1 ] || [ "$local_port" -gt 65535 ]; then
    echo "=> Invalid port. Exiting."
    exit 1
  fi
fi

echo "${local_port}" > "$(dirname "$0")/.tunnel-port"
trap 'rm -f "$(dirname "$0")/.tunnel-port"' EXIT

echo "=> Opening SSH tunnel: localhost:${local_port} -> server:8080"
echo "=> Swagger UI: http://localhost:${local_port}/docs"
echo "=> Press Ctrl-C to close the tunnel"
ssh -NL "${local_port}:localhost:8080" -p "${SERVER_PORT}" "${SERVER_USER_AT_IP}"
