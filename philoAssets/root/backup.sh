#!/usr/bin/env bash

function usage() {
cat <<EOF

Usage: $0 [OPTION]

Backup PhiloAssets data to a Swift backup service using rclone.

Maintains two copies on the remote:
  - latest/: synced every run (incremental)
  - weekly/: full copy refreshed once a week (Sundays), untouched other days

Setup:

Requires the following environment variables to be set in ${HOME}/.backup.env:
  - ASSETS_DIR: directory to backup
  - SB_USERNAME: username for the Swift Backup service
  - SB_DIR: directory to backup to, in the Swift Backup service
  - SB_NAME: name of the Swift Backup service

Your ~/.config/rclone/rclone.conf should be configured with the Swift Backup service.
Run setup.sh to configure everything automatically.


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

req_env_vars=( "ASSETS_DIR" "SB_USERNAME" "SB_DIR" "SB_NAME" )
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

if [ ! -d "${ASSETS_DIR}" ]; then
    echo "Assets directory '${ASSETS_DIR}' doesn't exist. Aborting."
    exit 1
fi

remote="${SB_USERNAME}:${SB_DIR}"

echo "Starting backup at $(date)..."

# --- Sync latest copy (incremental) ---

echo "Syncing latest copy to ${SB_NAME} (latest/)..."
rclone sync "${ASSETS_DIR}" "${remote}/latest/" --progress --fast-list
rc_latest=$?

if [ "${rc_latest}" -ne 0 ]; then
    echo "ERROR: Latest sync failed (code=${rc_latest})."
    exit 1
fi

echo "Latest copy synced successfully."

# --- Weekly copy (Sundays only) ---

day_of_week=$(date +%u)

if [ "${day_of_week}" -eq 7 ]; then
    echo "Sunday: refreshing weekly copy to ${SB_NAME} (weekly/)..."
    rclone sync "${ASSETS_DIR}" "${remote}/weekly/" --progress --fast-list
    rc_weekly=$?

    if [ "${rc_weekly}" -ne 0 ]; then
        echo "ERROR: Weekly sync failed (code=${rc_weekly})."
        exit 1
    fi

    echo "Weekly copy refreshed successfully."
else
    echo "Not Sunday (day=${day_of_week}), skipping weekly copy."
fi

echo "Backup completed successfully at $(date)."
