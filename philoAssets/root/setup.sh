#!/usr/bin/env bash

function usage() {
cat <<EOF

Usage: $0 [OPTION]

Configure backup infrastructure on the PhiloAssets server.
Must be executed as root. Reads credentials from /root/.backup.env.

Sets up:
  - rclone with the Swift Backup backend
  - exim4 as a smarthost relay for email alerts
  - cron job for nightly backups

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

if [ "${EUID}" -ne 0 ]; then
    echo "This script needs to be executed as root."
    exit 1
fi

if [ ! -f "${HOME}/.backup.env" ]; then
    echo "Missing ${HOME}/.backup.env. Copy .backup.env.example and fill in the values."
    exit 1
fi

source "${HOME}/.backup.env"

req_env_vars=( "ASSETS_DIR" "SB_USERNAME" "SB_KEY" "SB_AUTH" "SB_DIR" "SB_NAME" "SMTP_HOST" "SMTP_USER" "SMTP_PASS" "SMTP_SENDER_NAME" "ALERT_RECIPIENTS" )
error_msg=
error_flag=0

for var in "${req_env_vars[@]}"; do
    if [ -z "${!var}" ]; then
        error_msg="${error_msg}Environment variable '${var}' is not set.\n"
        error_flag=1
    fi
done

if [ "${error_flag}" -eq 1 ]; then
    echo -e "${error_msg}"
    exit 1
fi

# --- Install packages ---

echo "Installing required packages..."
apt update -qq
apt install -y -qq rclone exim4 mailutils cron > /dev/null
echo "Packages installed."

# --- Configure rclone ---

echo "Configuring rclone..."
mkdir -p /root/.config/rclone

printf '[%s]\n' "${SB_USERNAME}" > /root/.config/rclone/rclone.conf
printf 'type = swift\n' >> /root/.config/rclone/rclone.conf
printf 'user = %s\n' "${SB_USERNAME#sb_project_}" >> /root/.config/rclone/rclone.conf
printf 'key = %s\n' "${SB_KEY}" >> /root/.config/rclone/rclone.conf
printf 'auth = %s\n' "${SB_AUTH}" >> /root/.config/rclone/rclone.conf
printf 'domain = default\n' >> /root/.config/rclone/rclone.conf
printf 'tenant = %s\n' "${SB_USERNAME}" >> /root/.config/rclone/rclone.conf
printf 'tenant_domain = default\n' >> /root/.config/rclone/rclone.conf
printf 'region = RegionOne\n' >> /root/.config/rclone/rclone.conf
printf 'storage_url =\n' >> /root/.config/rclone/rclone.conf
printf 'auth_version =\n' >> /root/.config/rclone/rclone.conf

chmod 600 /root/.config/rclone/rclone.conf
echo "rclone configured."

# --- Test rclone ---

echo "Testing rclone connection..."
if rclone about "${SB_USERNAME}:" > /dev/null 2>&1; then
    echo "rclone connection successful."
else
    echo "ERROR: rclone connection failed. Check your SB_USERNAME, SB_KEY, and SB_AUTH."
    exit 1
fi

# --- Configure exim4 ---

echo "Configuring exim4 smarthost..."

cat > /etc/exim4/update-exim4.conf.conf <<EOF
dc_eximconfig_configtype='smarthost'
dc_other_hostnames=''
dc_local_interfaces='127.0.0.1 ; ::1'
dc_readhost='philosophie.ch'
dc_relay_domains=''
dc_minimaldns='false'
dc_relay_nets=''
dc_smarthost='${SMTP_HOST}::587'
CFILEMODE='644'
dc_use_split_config='false'
dc_hide_mailname='true'
dc_mailname_in_oh='true'
dc_localdelivery='mail_spool'
EOF

printf '%s:%s:%s\n' "${SMTP_HOST}" "${SMTP_USER}" "${SMTP_PASS}" > /etc/exim4/passwd.client
chmod 640 /etc/exim4/passwd.client
chown root:Debian-exim /etc/exim4/passwd.client

cat > /etc/email-addresses <<EOF
root: ${SMTP_SENDER_NAME} <${SMTP_USER}>
sysadmin: ${SMTP_SENDER_NAME} <${SMTP_USER}>
EOF

update-exim4.conf
systemctl restart exim4
echo "exim4 configured."

# --- Test email ---

echo "Sending test email to ${ALERT_RECIPIENTS}..."
echo "Test email from PhiloAssets server backup setup." \
    | mail -s "PhiloAssets backup: setup test" ${ALERT_RECIPIENTS}
echo "Test email sent. Check your inbox to confirm delivery."

# --- Install cron job ---

echo "Installing cron job..."
cron_line="0 0 * * * /root/cron-backup.sh >> /var/log/backup-verbose.log 2>&1"

if crontab -l 2>/dev/null | grep -qF "cron-backup.sh"; then
    echo "Cron job already exists, skipping."
else
    (crontab -l 2>/dev/null; echo "${cron_line}") | crontab -
    echo "Cron job installed: ${cron_line}"
fi

# --- Configure logrotate ---

echo "Configuring logrotate..."
cat > /etc/logrotate.d/backup <<'EOF'
/home/sysadmin/rootcron.log /var/log/backup-verbose.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
}
EOF
echo "Logrotate configured."

echo ""
echo "Setup complete. Run '/root/backup.sh' to test a manual backup."
