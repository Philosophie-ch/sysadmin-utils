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

echo "=> Opening SSH tunnel: localhost:${ALEXANDRIA_LOCAL_PORT} -> server:8080"
echo "=> Swagger UI: http://localhost:${ALEXANDRIA_LOCAL_PORT}/docs"
echo "=> Press Ctrl-C to close the tunnel"
ssh -NL "${ALEXANDRIA_LOCAL_PORT}:localhost:8080" -p "${SERVER_PORT}" "${SERVER_USER_AT_IP}"
