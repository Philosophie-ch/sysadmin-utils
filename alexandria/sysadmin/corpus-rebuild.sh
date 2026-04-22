#!/bin/bash -i
# Wipe prod data and reimport from the local corpus clone via SSH tunnel.
# Run tunnel.sh first, then this script.

if [ ! -f .env ]; then
  echo "=> No .env file found"
  exit 1
fi

set -o allexport
source .env
set +o allexport

required_vars=( "ALEXANDRIA_API_KEY" "ALEXANDRIA_LOCAL_PORT" "ALEXANDRIA_CORPUS_PATH" )

var_err_msg=
for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    var_err_msg="${var_err_msg}=> Error: Missing required environment variable: $var\n"
  fi
done

if [ -n "$var_err_msg" ]; then
  echo -e "$var_err_msg"
  echo "=> Please make sure the required environment variables are set in .env. Exiting."
  exit 1
fi

if [ ! -d "$ALEXANDRIA_CORPUS_PATH/data" ]; then
  echo "=> ERROR: corpus data/ not found at $ALEXANDRIA_CORPUS_PATH/data"
  echo "=> Run /alexandria-data-update first to populate the corpus."
  exit 1
fi

# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

API="http://localhost:${ALEXANDRIA_LOCAL_PORT}"
KEY="${ALEXANDRIA_API_KEY}"

print_target_banner "${ALEXANDRIA_LOCAL_PORT}"

# ── Version gate ──────────────────────────────────────────────────────────────
NEW_VERSION=$(python3 -c "
with open('${ALEXANDRIA_CORPUS_PATH}/data_version.yml') as f:
    for line in f:
        line = line.strip()
        if line.startswith('version:'):
            print(line.split(':', 1)[1].strip().strip('\"'))
            break
" 2>/dev/null || echo "")

CURRENT=$(curl -sf \
  "${API}/api/v1/data-version?limit=1&sort=imported_at&order=desc" \
  -H "Authorization: Bearer $KEY" \
  | python3 -c "
import json, sys
items = json.load(sys.stdin).get('items', [])
print(items[0]['version'] if items else '')
" 2>/dev/null || echo "")

echo "=> Current DB version: ${CURRENT:-none}"
echo "=> Corpus version:     ${NEW_VERSION:-unknown}"

if [ -n "$CURRENT" ] && [ "$CURRENT" = "$NEW_VERSION" ]; then
  echo "=> WARNING: DB is already at version $NEW_VERSION."
  read -r -p "=> Proceed anyway? [y/N] " confirm
  confirm="${confirm//$'\r'/}"
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "=> Aborted."
    exit 0
  fi
fi

# ── Wipe ──────────────────────────────────────────────────────────────────────
echo ""
echo "=> Wiping data..."
curl -sS --fail-with-body -X POST "${API}/api/v1/admin/wipe?confirm=true" \
  -H "Authorization: Bearer $KEY" | python3 -m json.tool

# ── Import ────────────────────────────────────────────────────────────────────
echo ""
echo "=> Importing from corpus..."
"${ALEXANDRIA_CORPUS_PATH}/scripts/import-from-corpus.sh" "$API" "$KEY"

# ── Record version ────────────────────────────────────────────────────────────
echo ""
echo "=> Recording data version..."
"${ALEXANDRIA_CORPUS_PATH}/scripts/record-data-version.sh" "$API" "$KEY"

echo ""
echo "=> Done."
