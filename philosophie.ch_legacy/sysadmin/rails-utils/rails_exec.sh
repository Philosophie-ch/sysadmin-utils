#!/usr/bin/env bash

function usage() {
cat <<EOF

Usage: $0 [OPTION] RAILS_CONSOLE_SCRIPT

Execute a Rails console script in the philosophie.ch_legacy Rails app in the Docker container.

Options:
  -h, --help      Show this help message and exit

EOF
}

function gen_uuid() {
  uuid=$( cat /proc/sys/kernel/random/uuid )

  if [ -z "${uuid}" ]; then
  # If /proc/sys/kernel/random/uuid is not available, use a method that works also on mac
  uuid=$( echo $(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1) )

  fi

  echo "${uuid}"
}

case "${1}" in
    "-h" | "--help")
        usage
        exit 0
        ;;
esac

# Check that a Rails console script was passed as an argument 
if [ -z "${1}" ]; then
    echo "A Rails console script must be passed as an argument."
    usage
    exit 1
fi


# 1. Identify the Rails container
# Extract containers sorted by creation date
rails_containers=$( docker ps --filter "name=philosophiechlegacy-web" --format "{{.ID}} {{.CreatedAt}}" | sort -k 2 -r | awk '{print $1}' )
# Get the most recently created one
rails_container=$( echo "${rails_containers}" | head -n 1 )

# 2. Put the script inside the container, at /app/tmp
# But put a uuid4 at the end of its name first
script_name=$( basename "${1}" )
uuid=$( gen_uuid )
container_script="${script_name}-${uuid}"
docker cp "${script_name}" "${rails_container}:/app/tmp/${container_script}"

# 3. Execute the script in the Rails container
docker exec -it "${rails_container}" /bin/bash -c "cd /app && bundle exec rails runner /app/tmp/${container_script}"

# 4. Cleanup
docker exec -it "${rails_container}" /bin/bash -c "rm -f /app/tmp/${container_script}"

