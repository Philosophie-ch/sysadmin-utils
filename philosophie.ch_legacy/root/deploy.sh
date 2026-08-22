#!/usr/bin/env bash
set -e

# Must match an entry in ~/.ssh/config
SERVER="philo-000"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Deploying backup scripts to ${SERVER}..."
rsync -avP \
    "${SCRIPT_DIR}/dump-assets-db.sh" \
    "${SCRIPT_DIR}/trigger-backup.sh" \
    "${SCRIPT_DIR}/run-backup.sh" \
    "${SERVER}:/tmp/"

ssh -t "${SERVER}" "sudo cp /tmp/dump-assets-db.sh /tmp/trigger-backup.sh /tmp/run-backup.sh /root/ && sudo chmod 700 /root/dump-assets-db.sh /root/trigger-backup.sh /root/run-backup.sh && sudo chown root:root /root/dump-assets-db.sh /root/trigger-backup.sh /root/run-backup.sh && rm /tmp/dump-assets-db.sh /tmp/trigger-backup.sh /tmp/run-backup.sh"

echo "All scripts deployed to ${SERVER}:/root/"
