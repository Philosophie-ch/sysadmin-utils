#!/usr/bin/env bash

function usage() {
cat <<EOF

Usage: $0 [OPTION]

Dumps the Alexandria Nexus PostgreSQL database to a backup directory.
Produces a full dump and a data-only dump.
Needs to be executed as root. Designed to run as a cron job.

Setup:

Requires the following environment variables set in ${HOME}/.alexandria-backup.env:
  - SYSADMIN_USERNAME: user that will own the backup files
  - BACKUP_DIR: directory to write dumps to
  - RETENTION_DAYS: number of days of dumps to keep (e.g. 7)
  - DB_CONTAINER_NAME: name of the postgres container (e.g. alexandria-db)

Options:
  -h, --help      Show this help message and exit

EOF
}

case "${1}" in
    "-h" | "--help")
        usage
        exit 0
        ;;
esac

set -e
source "${HOME}/.alexandria-backup.env"
set +e

req_env_vars=( "SYSADMIN_USERNAME" "BACKUP_DIR" "RETENTION_DAYS" "DB_CONTAINER_NAME" )
error_msg=
error_flag=0

for var in "${req_env_vars[@]}"; do
    if [ -z "${!var}" ]; then
        error_msg="${error_msg}Environment variable '${var}' is not set.\n"
        error_flag=1
    fi
done

if [ "${error_flag}" -eq 1 ]; then
    echo -e "${error_msg}"
    echo "Please set the required environment variables in '${HOME}/.alexandria-backup.env'."
    exit 1
fi

set -e

timestamp=$(date +%Y%m%d_%H%M%S)
dump_full="${BACKUP_DIR}/alexandria_${timestamp}.sql"
dump_data="${BACKUP_DIR}/alexandria_data_${timestamp}.sql"

echo "Setting up backup directory..."
mkdir -p "${BACKUP_DIR}"

echo "Dumping Alexandria database (full)..."
docker exec "${DB_CONTAINER_NAME}" /bin/sh -c \
    'pg_dump "postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@127.0.0.1/${POSTGRES_DB}" --column-inserts --no-owner --no-privileges' \
    > "${dump_full}" && echo "Full dump done." || echo "Failed to dump database."

echo "Dumping Alexandria database (data-only)..."
docker exec "${DB_CONTAINER_NAME}" /bin/sh -c \
    'pg_dump "postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@127.0.0.1/${POSTGRES_DB}" --column-inserts --data-only --no-owner --no-privileges' \
    > "${dump_data}" && echo "Data-only dump done." || echo "Failed to dump data-only database."

echo "Setting permissions..."
chown "${SYSADMIN_USERNAME}:${SYSADMIN_USERNAME}" "${dump_full}" "${dump_data}"
chmod 640 "${dump_full}" "${dump_data}"

echo "Removing dumps older than ${RETENTION_DAYS} days..."
find "${BACKUP_DIR}" -name "alexandria_*.sql.gz" -mtime +"${RETENTION_DAYS}" -delete
echo "Retention cleanup done."

echo "Finished dump!"
