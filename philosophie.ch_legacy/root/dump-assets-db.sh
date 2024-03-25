#!/usr/bin/env bash

function usage() {
cat <<EOF

Usage: $0 [OPTION]

Dumps the philosophie.ch_legacy rails assets and postgres database to a backup directory. Needs to be executed as root. This can be executed as a cron job.

Setup:

Requires the following environment variables to be set in ${HOME}/.backup.env:
  - SYSADMIN_USERNAME: username of a user with privileges
  - LOCAL_BACKUP_DIR: directory to backup to
  - RAILS_ASSETS_TO_BACKUP_DIR: directory containing the rails assets to backup
  - DB_TO_BACKUP_DIR: directory to backup the database dump to
  - CONTAINER_DB_TO_BACKUP_DIR: directory in the database container to backup the database dump to. Should be mounted to DB_TO_BACKUP_DIR
  - DB_CONTAINER_NAME: name of the database container
  - DB_DUMP_NAME: basename of the database dump


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
source "${HOME}/.backup.env"
set +e

req_env_vars=( "SYSADMIN_USERNAME" "LOCAL_BACKUP_DIR" "RAILS_ASSETS_TO_BACKUP_DIR" "DB_TO_BACKUP_DIR" "DB_CONTAINER_NAME" "CONTAINER_DB_TO_BACKUP_DIR" "DB_DUMP_NAME" )
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
    echo "Please set the required environment variables in '${HOME}/.backup.env'."
    exit 1
fi


echo "Setting up backup directories..."
mkdir -p "${LOCAL_BACKUP_DIR}"
mkdir -p "${LOCAL_BACKUP_DIR}/public"
mkdir -p "${DB_TO_BACKUP_DIR}"
echo "Backup directories set up."

# Backup rails assets
echo "Backing up rails assets..."
echo "Assets: ${LOCAL_BACKUP_DIR}/storage"
rsync -avzP -L -K --delete --force "${RAILS_ASSETS_TO_BACKUP_DIR}/storage" "${LOCAL_BACKUP_DIR}"

echo "Assets: ${LOCAL_BACKUP_DIR}/uploads"
rsync -avzP -L -K --delete --force "${RAILS_ASSETS_TO_BACKUP_DIR}/uploads" "${LOCAL_BACKUP_DIR}"

echo "Assets: ${LOCAL_BACKUP_DIR}/public/system"
rsync -avzP -L -K --delete --force "${RAILS_ASSETS_TO_BACKUP_DIR}/public/system" "${LOCAL_BACKUP_DIR}/public/system"

echo "Assets: ${LOCAL_BACKUP_DIR}/public/pictures"
rsync -avzP -L -K --delete --force "${RAILS_ASSETS_TO_BACKUP_DIR}/public/pictures" "${LOCAL_BACKUP_DIR}/public/pictures"

echo "Backing up rails assets done."

# Backup database
echo "Backing up database..."
rm -f "${DB_TO_BACKUP_DIR}/${DB_DUMP_NAME}"
docker exec "${DB_CONTAINER_NAME}" /bin/bash -c "pg_dump \"postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@127.0.0.1/\${POSTGRES_DB}\" --column-inserts --no-owner --no-privileges > ${CONTAINER_DB_TO_BACKUP_DIR}/${DB_DUMP_NAME}" && echo "Database dump done." || echo "Failed to dump database."
rm -f "${LOCAL_BACKUP_DIR}/${DB_DUMP_NAME}"
rsync -avP "${DB_TO_BACKUP_DIR}/${DB_DUMP_NAME}" "${LOCAL_BACKUP_DIR}"
echo "Backing up database step culminated."


# Set up permissions
echo "Setting up permissions..."
chown -R ${SYSADMIN_USERNAME}:${SYSADMIN_USERNAME} "${LOCAL_BACKUP_DIR}"
chmod -R 740 "${LOCAL_BACKUP_DIR}"
chmod 770 "${LOCAL_BACKUP_DIR}"
echo "Permissions set up."

echo "Finished dump!"
