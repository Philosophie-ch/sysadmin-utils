#!/usr/bin/env bash
set -e

# Must match an entry in ~/.ssh/config
SERVER="philo-assets"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Deploying backup scripts to ${SERVER}..."
rsync -avP \
    "${SCRIPT_DIR}/backup.sh" \
    "${SCRIPT_DIR}/cron-backup.sh" \
    "${SCRIPT_DIR}/setup.sh" \
    "${SCRIPT_DIR}/.backup.env" \
    "${SERVER}:/tmp/"

ssh -t "${SERVER}" "sudo cp /tmp/backup.sh /tmp/cron-backup.sh /tmp/setup.sh /tmp/.backup.env /root/ && sudo chmod 700 /root/backup.sh /root/cron-backup.sh /root/setup.sh && sudo chmod 600 /root/.backup.env && sudo chown root:root /root/backup.sh /root/cron-backup.sh /root/setup.sh /root/.backup.env && rm /tmp/backup.sh /tmp/cron-backup.sh /tmp/setup.sh /tmp/.backup.env"

echo "All scripts deployed to ${SERVER}:/root/"
echo ""
echo "Next steps:"
echo "  1. SSH into the server: ssh ${SERVER}"
echo "  2. Run setup:           sudo /root/setup.sh"
echo "  3. Test backup:         sudo /root/backup.sh"
