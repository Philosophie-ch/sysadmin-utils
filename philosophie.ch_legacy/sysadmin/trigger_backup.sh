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


## SET THE CORRECT DIRECTORIES HERE
rails_dir="/home/sysadmin/philosophiechlegacy"
db_dir="/home/sysadmin/philosophiechlegacy-db/data"
##

echo "Backing up philosophie.ch legacy data to Infomaniak's Swiss Backup..."

echo "Setting up backup directories..."
ts=$( date +%Y%m%d )
base_dir="/home/sysadmin/backups"
bak_dir="${base_dir}/${ts}"
mkdir -p "${bak_dir}"
mkdir -p "${bak_dir}/public"
mkdir -p "${db_dir}"
echo "Backup directories set up."

# Backup rails assets
echo "Backing up rails assets..."
echo "Assets: ${bak_dir}/storage"
cp -r "${rails_dir}/storage" "${bak_dir}"
echo "Assets: ${bak_dir}/uploads"
cp -r "${rails_dir}/uploads" "${bak_dir}"
echo "Assets: ${bak_dir}/public/system"
cp -r "${rails_dir}/public/system" "${bak_dir}/public/system"
echo "Assets: ${bak_dir}/public/pictures"
cp -r "${rails_dir}/public/pictures" "${bak_dir}/public/pictures"
echo "Backing up rails assets done."

# Backup database
echo "Backing up database..."
docker exec philosophiechlegacy-db /bin/bash -c "pg_dump \"postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@127.0.0.1/\${POSTGRES_DB}\" --column-inserts --no-owner --no-privileges > /var/lib/postgresql/data/backup.dump"
sudo cp "${db_dir}/backup.dump" "${bak_dir}"
echo "Backing up database done."


# Set up permissions
echo "Setting up permissions..."
sudo chown sysadmin:sysadmin "${bak_dir}"
echo "Permissions set up."


# Configured to use Infomaniak's Swiss Backup
echo "Syncing backup to Infomaniak's Swiss Backup..."
rclone sync /home/sysadmin/backups sb_project_SBI-LB170495:philosophie.ch/backups
echo "Syncing backup to Infomaniak's Swiss Backup done."

