#!/usr/bin/env bash

function usage() {
cat <<EOF

Usage: $0 [OPTION]

Backup philosophie.ch legacy data to a Swift backup service using rclone.
This can be executed as a cron job.

DB dumps are uploaded to dated directories with a retention policy:
  - 1 per day for the past 7 days
  - 1 per week for the past 3 months
  - 1 per month for the past 6 months

Assets (non-DB files) are synced to a separate directory without versioning.

Setup:

Requires the following environment variables to be set in ${HOME}/.backup.env:
  - LOCAL_BACKUP_DIR: directory to backup
  - SB_USERNAME: username for the Swift Backup service
  - SB_DIR: directory to backup to, in the Swift Backup service
  - SB_NAME: name of the Swift Backup service
  - DB_DUMP_NAME: filename of the binary DB dump
  - DB_DATA_DUMP_NAME: filename of the SQL DB dump

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

req_env_vars=( "LOCAL_BACKUP_DIR" "SB_USERNAME" "SB_DIR" "SB_NAME" "DB_DUMP_NAME" "DB_DATA_DUMP_NAME" )
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

db_dump="${LOCAL_BACKUP_DIR}/${DB_DUMP_NAME}"
db_data_dump="${LOCAL_BACKUP_DIR}/${DB_DATA_DUMP_NAME}"

if [ ! -f "${db_dump}" ] || [ ! -f "${db_data_dump}" ]; then
    echo "DB dump files not found in ${LOCAL_BACKUP_DIR}. Aborting."
    exit 1
fi

remote="${SB_USERNAME}:${SB_DIR}"
today=$(date +"%Y-%m-%d")

echo "Starting backup at $(date)..."

# --- Upload today's DB dumps to a dated directory ---

echo "Uploading DB dumps to ${SB_NAME} (db/${today})..."
rclone copy "${db_dump}" "${remote}/db/${today}/"
rc_dump=$?

rclone copy "${db_data_dump}" "${remote}/db/${today}/"
rc_data=$?

if [ "${rc_dump}" -ne 0 ] || [ "${rc_data}" -ne 0 ]; then
    echo "ERROR: DB dump upload failed (dump=${rc_dump}, data=${rc_data})."
    exit 1
fi

echo "DB dumps uploaded successfully."

# --- Sync assets (everything except DB dumps) ---

echo "Syncing assets to ${SB_NAME} (assets/)..."
rclone sync "${LOCAL_BACKUP_DIR}" "${remote}/assets/" \
    --exclude "${DB_DUMP_NAME}" \
    --exclude "${DB_DATA_DUMP_NAME}"
rc_assets=$?

if [ "${rc_assets}" -ne 0 ]; then
    echo "ERROR: Asset sync failed (code=${rc_assets})."
    exit 1
fi

echo "Assets synced successfully."

# --- Prune old DB snapshots ---
#
# Retention policy:
#   < 7 days old:    keep (daily)
#   7-90 days old:   keep one per ISO week (the most recent)
#   90-180 days old: keep one per month (the most recent)
#   > 180 days old:  delete

echo "Applying retention policy..."

prune_errors=0

while IFS= read -r dir_name; do
    dir_name="${dir_name%/}"

    if ! date -d "${dir_name}" +%s >/dev/null 2>&1; then
        continue
    fi

    dir_epoch=$(date -d "${dir_name}" +%s)
    now_epoch=$(date +%s)
    age_days=$(( (now_epoch - dir_epoch) / 86400 ))

    if [ "${age_days}" -lt 7 ]; then
        continue
    fi

    keep=0

    if [ "${age_days}" -le 90 ]; then
        dir_week=$(date -d "${dir_name}" +%G-W%V)
        latest_in_week=""
        while IFS= read -r sibling; do
            sibling="${sibling%/}"
            date -d "${sibling}" +%s >/dev/null 2>&1 || continue
            sibling_week=$(date -d "${sibling}" +%G-W%V)
            if [ "${sibling_week}" = "${dir_week}" ]; then
                if [ -z "${latest_in_week}" ] || [[ "${sibling}" > "${latest_in_week}" ]]; then
                    latest_in_week="${sibling}"
                fi
            fi
        done < <(rclone lsf "${remote}/db/" --dirs-only)
        if [ "${dir_name}" = "${latest_in_week}" ]; then
            keep=1
        fi
    elif [ "${age_days}" -le 180 ]; then
        dir_month=$(date -d "${dir_name}" +%Y-%m)
        latest_in_month=""
        while IFS= read -r sibling; do
            sibling="${sibling%/}"
            date -d "${sibling}" +%s >/dev/null 2>&1 || continue
            sibling_month=$(date -d "${sibling}" +%Y-%m)
            if [ "${sibling_month}" = "${dir_month}" ]; then
                if [ -z "${latest_in_month}" ] || [[ "${sibling}" > "${latest_in_month}" ]]; then
                    latest_in_month="${sibling}"
                fi
            fi
        done < <(rclone lsf "${remote}/db/" --dirs-only)
        if [ "${dir_name}" = "${latest_in_month}" ]; then
            keep=1
        fi
    fi

    if [ "${keep}" -eq 0 ]; then
        echo "Pruning db/${dir_name} (${age_days} days old)..."
        if ! rclone purge "${remote}/db/${dir_name}"; then
            echo "WARNING: Failed to prune db/${dir_name}."
            prune_errors=$((prune_errors + 1))
        fi
    fi
done < <(rclone lsf "${remote}/db/" --dirs-only)

if [ "${prune_errors}" -gt 0 ]; then
    echo "WARNING: ${prune_errors} prune operation(s) failed."
fi

echo "Backup completed successfully at $(date)."
