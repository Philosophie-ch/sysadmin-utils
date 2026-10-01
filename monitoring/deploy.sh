#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "${SCRIPT_DIR}/.env" ]; then
    echo "Error: .env file not found. Copy .env.example to .env and fill in the values."
    exit 1
fi

source "${SCRIPT_DIR}/.env"

if [ -z "${MONITOR_SERVER}" ] || [ -z "${ASSETS_SERVER}" ]; then
    echo "Error: MONITOR_SERVER and ASSETS_SERVER must be set in .env"
    exit 1
fi

echo "=== Deploying monitoring stack ==="

echo ""
echo "--- Assets server (${ASSETS_SERVER}): exporters ---"
echo "1. Syncing exporter config..."
ssh "${ASSETS_SERVER}" "mkdir -p ~/monitoring"
rsync -avq \
    "${SCRIPT_DIR}/philo-assets/docker-compose.yml" \
    "${SCRIPT_DIR}/philo-assets/.env.example" \
    "${ASSETS_SERVER}:~/monitoring/"
ssh "${ASSETS_SERVER}" "cd ~/monitoring && [ ! -f .env ] && cp .env.example .env || true"

echo "2. Starting exporters..."
ssh "${ASSETS_SERVER}" "cd ~/monitoring && docker compose up -d"

echo ""
echo "--- Monitor server (${MONITOR_SERVER}): stack + tunnel ---"
echo "3. Syncing monitoring config..."
rsync -avq --delete \
    --exclude '.env' \
    --exclude 'philo-assets/.env' \
    "${SCRIPT_DIR}/" "${MONITOR_SERVER}:~/sysadmin-utils/monitoring/"

echo "4. Restarting monitoring stack..."
ssh "${MONITOR_SERVER}" "cd ~/sysadmin-utils/monitoring && docker compose down && docker compose up -d"

echo "5. Setting up SSH tunnel service..."
ssh "${MONITOR_SERVER}" "chmod +x ~/sysadmin-utils/monitoring/philo-assets/ssh-tunnel.sh"
ssh -t "${MONITOR_SERVER}" "\
    DEPLOY_PATH=\$(realpath ~/sysadmin-utils/monitoring) && \
    sed \"s|DEPLOY_PATH_PLACEHOLDER|\${DEPLOY_PATH}|g\" ~/sysadmin-utils/monitoring/philo-assets/ssh-tunnel.service | sudo tee /etc/systemd/system/monitoring-tunnel.service > /dev/null && \
    sudo chmod 644 /etc/systemd/system/monitoring-tunnel.service && \
    sudo systemctl daemon-reload && \
    sudo systemctl enable monitoring-tunnel && \
    sudo systemctl restart monitoring-tunnel"

echo "6. Checking tunnel status..."
ssh "${MONITOR_SERVER}" "systemctl is-active monitoring-tunnel && echo 'Tunnel is running' || echo 'Tunnel failed to start'"

echo ""
echo "=== Done ==="
echo "Access Grafana: ssh -L ${GRAFANA_PORT:-3009}:localhost:${GRAFANA_PORT:-3009} ${MONITOR_SERVER}"
echo "Then open http://localhost:${GRAFANA_PORT:-3009}"
