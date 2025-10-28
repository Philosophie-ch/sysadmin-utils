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

echo "=> Backing up existing local reports (if any)"
if [ -d "portal-tasks-reports" ]; then
  timestamp=$(date +%Y%m%d_%H%M%S)
  mv portal-tasks-reports "portal-tasks-reports.backup.${timestamp}"
  echo "   Backed up to: portal-tasks-reports.backup.${timestamp}"
fi

echo "=> Cleaning old reports on server"
ssh -p ${SERVER_PORT} ${SERVER_USER_AT_IP} "rm -rf ${SERVER_REPORTS_PATH}/portal-tasks-reports"

echo "=> Pulling all reports files from the container"
if ssh -p ${SERVER_PORT} ${SERVER_USER_AT_IP} "cd ${SERVER_REPORTS_PATH} && rails_container=\$(docker ps --format '{{.Names}}' | grep ${SERVER_CONTAINER_BASENAME}) && docker cp \$rails_container:/rails/portal-tasks-reports ."; then
  echo "   Successfully copied reports from container"
else
  echo "   WARNING: No reports found in container (this is normal if you haven't generated any reports yet)"
  echo "   Skipping pull. Your local backup (if any) is preserved."
  exit 0
fi

echo "=> Pulling all *_report.csv files from the server"
if rsync -avzP --delete -L -K -e "ssh -p ${SERVER_PORT}" "${SERVER_USER_AT_IP}:${SERVER_REPORTS_PATH}/portal-tasks-reports" .; then
  echo "   Successfully pulled reports from server"

  # Only remove backup if pull was successful
  if ls portal-tasks-reports.backup.* 1> /dev/null 2>&1; then
    echo "=> Removing backup (pull successful)"
    rm -rf portal-tasks-reports.backup.*
  fi
else
  echo "   ERROR: Failed to pull reports from server"
  echo "   Restoring backup..."
  if ls portal-tasks-reports.backup.* 1> /dev/null 2>&1; then
    latest_backup=$(ls -t portal-tasks-reports.backup.* | head -1)
    mv "$latest_backup" portal-tasks-reports
    echo "   Restored from: $latest_backup"
  fi
  exit 1
fi

echo "=> Cleanup container"
ssh -p ${SERVER_PORT} ${SERVER_USER_AT_IP} "cd ${SERVER_REPORTS_PATH} && rails_container=\$(docker ps --format '{{.Names}}' | grep ${SERVER_CONTAINER_BASENAME}) && docker exec \$rails_container rm -rf /rails/portal-tasks-reports"

echo "=> Pull complete"

