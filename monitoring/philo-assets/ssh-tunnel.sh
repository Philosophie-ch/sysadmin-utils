#!/usr/bin/env bash

# SSH tunnel between the monitoring server and the assets server.
# Local forwards: node_exporter and cAdvisor, for Prometheus remote scraping.
# Reverse forward: Loki, so the assets server's Alloy can push logs.
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
LOCAL_LOKI="${LOKI_PORT}"
REMOTE_LOKI="${ASSETS_LOKI_PUSH_PORT}"

if [ -z "${REMOTE_HOST}" ] || [ -z "${LOCAL_NE}" ] || [ -z "${LOCAL_CA}" ] || [ -z "${REMOTE_NE}" ] || [ -z "${REMOTE_CA}" ] || [ -z "${LOCAL_LOKI}" ] || [ -z "${REMOTE_LOKI}" ]; then
    echo "Error: ASSETS_SERVER, TUNNEL_NODE_EXPORTER_PORT, TUNNEL_CADVISOR_PORT, ASSETS_NODE_EXPORTER_PORT, ASSETS_CADVISOR_PORT, LOKI_PORT, ASSETS_LOKI_PUSH_PORT must be set in .env"
    exit 1
fi

exec ssh -N \
  -L "${LOCAL_NE}:localhost:${REMOTE_NE}" \
  -L "${LOCAL_CA}:localhost:${REMOTE_CA}" \
  -R "127.0.0.1:${REMOTE_LOKI}:localhost:${LOCAL_LOKI}" \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o ExitOnForwardFailure=yes \
  "${REMOTE_HOST}"
