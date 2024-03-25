#!/usr/bin/env bash

function usage() {
cat <<EOF

Usage: $0 [OPTION]

Backup philosophie.ch legacy data to a Swift backup service using rclone.
This can be executed as a cron job.

Setup:

Requires the following environment variables to be set in ${HOME}/.backup.env:
  - LOCAL_BACKUP_DIR: directory to backup
  - SB_USERNAME: username for the Swift Backup service
  - SB_DIR: directory to backup to, in the Swift Backup service
  - SB_NAME: name of the Swift Backup service

Your ~/.config/rclone/rclone.conf should be configured with the Swift Backup service in question.


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

req_env_vars=( "LOCAL_BACKUP_DIR" "SB_USERNAME" "SB_DIR" "SB_NAME" )
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

if [ ! -d "${LOCAL_BACKUP_DIR}" ]; then
    echo "Backup directory doesn't exist. Aborting."
    exit 1
fi

ts=$(date +"%Y%m%d-%H%M%S")
echo "Starting backup at ${ts}..."
backup_dir_ts="${LOCAL_BACKUP_DIR}-${ts}"

mv "${LOCAL_BACKUP_DIR}" "${backup_dir_ts}"

echo "Backing up data to ${SB_NAME}..."
rclone sync "${backup_dir_ts}" "${SB_USERNAME}:${SB_DIR}" && mv "${backup_dir_ts}" "${LOCAL_BACKUP_DIR}" || mv "${backup_dir_ts}" "${LOCAL_BACKUP_DIR}"

echo "Syncing backup to ${SB_NAME} culminated with code: ${?}"

