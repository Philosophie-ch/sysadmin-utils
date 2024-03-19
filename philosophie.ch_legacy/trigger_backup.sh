#!/usr/bin/env bash

function usage() {
cat <<EOF

Usage: $0 [OPTION]

Backup philosophie.ch legacy data to Infomaniak's Swiss Backup.
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


ts=$( date +%Y%m%d )
base_dir="/home/sysadmin/backups"

bak_dir="${base_dir}/${ts}"
mkdir -p "${bak_dir}"
mkdir -p "${bak_dir}/public"


# Backup rails assets
rails_dir="/home/sysadmin/philosophiechlegacy"

cp -r "${rails_dir}/storage" "${bak_dir}"
cp -r "${rails_dir}/uploads" "${bak_dir}"
cp -r "${rails_dir}/public/system" "${bak_dir}/public/system"
cp -r "${rails_dir}/public/pictures" "${bak_dir}/public/pictures"

# Backup database
docker exec philosophiechlegacy-db /bin/bash -c "pg_dump \"postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@127.0.0.1/\${POSTGRES_DB}\" --column-inserts --no-owner --no-privileges > /var/lib/postgresql/data/backup.dump"

db_dir="/home/sysadmin/philosophiechlegacy-db/data"
cp "${db_dir}/backup.dump" "${bak_dir}"


# Configured to use Infomaniak's Swiss Backup
rclone sync /home/sysadmin/backups sb_project_SBI-LB170495:philosophie.ch/backups

