#!/usr/bin/env bash

function usage() {
cat <<EOF
Usage: $0

This script is used to clear the cache of the rails application.
Uses the `Rails.cache.clear` method so it clears all the cache, independently of it being local or not (memcached, redis, etc).
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

docker exec "${rails_container}" bundle exec rails runner -e production "Rails.cache.clear" && echo "Rails cache cleared on $(date)" >> ~/cron.log || echo "Rails cache clear failed on $(date)" >> ~/cron.log

