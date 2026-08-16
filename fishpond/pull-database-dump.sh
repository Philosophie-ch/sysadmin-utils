#!/bin/bash
set -euo pipefail

SSH_KEY="$HOME/.ssh/id_rsaPhilippBlum"
SSH_USER="deploy"
SERVER="159.65.120.231"
REMOTE_APP_DIR="/home/sandro/dialectica"
REMOTE_DUMP="/home/deploy/latest.dump"
BACKUP_DIR="$HOME/philosophie-ch/backups/dialectica"
DATE="$(date +%y-%m-%d)"
DUMP_FILE="${BACKUP_DIR}/${DATE}.dump"

if [ -f "$DUMP_FILE" ]; then
  echo "Backup already exists for today: ${DUMP_FILE}"
  echo "Remove it first if you want a fresh dump."
  exit 1
fi

echo "=> Creating dump on server..."
ssh -i "$SSH_KEY" "${SSH_USER}@${SERVER}" \
  "PGPASSWORD=\$(grep DIALECTICA_DATABASE_PASSWORD /home/sandro/.bashrc | head -1 | cut -d'\"' -f2) pg_dump --format=custom -U sandro -h localhost dialectica_production > ${REMOTE_DUMP}"

echo "=> Pulling dump..."
mkdir -p "$BACKUP_DIR"
rsync -avzP -e "ssh -i ${SSH_KEY}" "${SSH_USER}@${SERVER}:${REMOTE_DUMP}" "$DUMP_FILE"

echo "=> Done. Dump saved to: ${DUMP_FILE}"
ls -lh "$DUMP_FILE"
