#!/bin/bash -i

# Load the environment variables
if [ ! -f .env ]; then
  echo "=> No .env file found"
  exit 1
fi

set -o allexport
source .env set
set +o allexport

# Check that the required environment variables exist, exit if not
required_vars=( "SERVER_USER_AT_IP" "SERVER_PORT" "SERVER_REPORTS_PATH" "SERVER_CONTAINER_BASENAME" )

var_err_msg=
for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    var_err_msg="${var_err_msg}=> Error: Missing required environment variable: $var\n"
  fi
done

if [ ! -z "$var_err_msg" ]; then
  echo -e "$var_err_msg"
  echo "=> Please make sure the required environment variables are set in .env.development. Exiting."
  exit 1
fi


# MAIN

echo "=> Pushing dltc-web HTML files to the server"
rsync -avzP --delete -L -K -e "ssh -p ${SERVER_PORT}" dltc-web "${SERVER_USER_AT_IP}:${SERVER_REPORTS_PATH}"

echo "=> Pushing dltc-web HTML files to the container"
ssh -p ${SERVER_PORT} ${SERVER_USER_AT_IP} "rails_container=\$(docker ps --format '{{.Names}}' | grep ${SERVER_CONTAINER_BASENAME}) && docker cp ${SERVER_REPORTS_PATH}/dltc-web \$rails_container:/rails"

echo "=> Push complete"

