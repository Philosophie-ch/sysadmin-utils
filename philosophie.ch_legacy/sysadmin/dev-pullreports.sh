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
required_vars=( "DEV_CONTAINER_BASENAME" )

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

echo "=> Cleaning old reports"
rm -rf portal-tasks-reports

echo "=> Pulling all reports files from the container"
rails_container=$(docker ps --format '{{.Names}}' | grep ${DEV_CONTAINER_BASENAME})
docker cp "${rails_container}:/app/portal-tasks-reports" .

echo "=> Cleanup container"
docker exec $rails_container rm -rf /app/portal-tasks-reports

echo "=> Pull complete"

