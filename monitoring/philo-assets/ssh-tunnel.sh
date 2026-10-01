#!/usr/bin/env bash

# SSH tunnel from the monitoring server to the assets server for Prometheus remote scraping.
# Forwards node_exporter and cAdvisor ports.
#
# Run on the monitoring server. Stays in the foreground; managed by systemd.
# Reconnects automatically on failure via ServerAliveInterval.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"

if [ -f "${ENV_FILE}" ]; then
    source "${ENV_FILE}"
fi

REMOTE_HOST="${ASSETS_SERVER}"
LOCAL_NE="${TUNNEL_NODE_EXPORTER_PORT}"
LOCAL_CA="${TUNNEL_CADVISOR_PORT}"
REMOTE_NE="${ASSETS_NODE_EXPORTER_PORT}"
REMOTE_CA="${ASSETS_CADVISOR_PORT}"

if [ -z "${REMOTE_HOST}" ] || [ -z "${LOCAL_NE}" ] || [ -z "${LOCAL_CA}" ] || [ -z "${REMOTE_NE}" ] || [ -z "${REMOTE_CA}" ]; then
    echo "Error: ASSETS_SERVER, TUNNEL_NODE_EXPORTER_PORT, TUNNEL_CADVISOR_PORT, ASSETS_NODE_EXPORTER_PORT, ASSETS_CADVISOR_PORT must be set in .env"
    exit 1
fi

exec ssh -N \
  -L "${LOCAL_NE}:localhost:${REMOTE_NE}" \
  -L "${LOCAL_CA}:localhost:${REMOTE_CA}" \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o ExitOnForwardFailure=yes \
  "${REMOTE_HOST}"
