#!/bin/bash -i

if [ ! -f .env ]; then
  echo "=> No .env file found"
  exit 1
fi

set -o allexport
source .env
set +o allexport

required_vars=( "SERVER_USER_AT_IP" "SERVER_PORT" )

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

tail_lines=50
if [ "$1" = "--tail" ] && [ -n "$2" ]; then
  tail_lines="$2"
fi

# MAIN

echo "=> Target: PROD (direct SSH to ${SERVER_USER_AT_IP})"
echo "=> Streaming Alexandria logs (last ${tail_lines} lines, Ctrl-C to stop)..."
ssh -p "${SERVER_PORT}" "${SERVER_USER_AT_IP}" "docker logs alexandria --tail ${tail_lines} -f"
