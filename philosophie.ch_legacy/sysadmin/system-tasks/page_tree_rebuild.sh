#!/usr/bin/env bash

function usage() {
cat <<EOF
Usage: $0

Numbers the page tree of the portal (lft, rgt, depth of alchemy_pages) again from parent_id, with the
pages:rebuild_tree task. Writes only those three columns, in one transaction, rolled back if the result is
not a valid tree. Deletes nothing. Runbook: doc/page_restore.md in the portal, "The page tree".
This can be executed as a cron job.

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


rails_container=$( docker ps --format '{{.Names}}' | grep 'philosophiechlegacy-web' )

output=$( docker exec -e APPLY=1 "${rails_container}" bin/rails pages:rebuild_tree 2>&1 ) && echo "Page tree rebuilt on $(date): $(echo "${output}" | tail -3 | tr '\n' ' ')" >> ~/cron.log || echo "Page tree rebuild failed on $(date): $(echo "${output}" | tail -3 | tr '\n' ' ')" >> ~/cron.log
