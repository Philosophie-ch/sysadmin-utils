#!/usr/bin/env bash

function usage() {
cat <<EOF

Usage: ${0} [OPTION] ENV_FILE

Setup basic sysadmin configuration for philosophie.ch_legacy.
This script is meant to be executed as the root of your server, and it assumes you already have ssh access to it.
Needs to be passed, as an argument, an environment file with the following variables:
  - SUDOER_PASSWORD: password for the sysadmin user

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

echo "Setting up basic sysadmin configuration for philosophie.ch_legacy..."
# Check if the script is being executed as root
if [ "${EUID}" -ne 0 ]; then
    echo "This script needs to be executed as root."
    exit 1
fi

# Check if the system is Debian
if [ ! -f /etc/debian_version ]; then
    echo "This script is meant to be executed on a Debian-based system."
    exit 1
fi

# Load environment variables: sudoer password
source "${1}"

# Assert that the required environment variables are set
req_vars=( "SUDOER_PASSWORD" )
err_msg=
for var in "${req_vars[@]}"; do
    if [ -z "${!var}" ]; then
        err_msg="${err_msg}Variable ${var} is not set.\n"
    fi
done

if [ -n "${err_msg}" ]; then
    echo -e "${err_msg}"
    usage
    exit 1
fi
echo "Environment variables loaded. Proceeding with the setup..."

# Update, and install required packages
echo "Updating and installing required packages..."
apt update && apt upgrade -y && apt autoremove -y
apt install -y sudo rsync openssh-server vim git curl wget unzip zip tar rclone cron
echo "Packages installed."
echo "Please also install Docker and Docker Compose, following the official documentation."

# Create sysadmin user
echo "Creating sysadmin user..."
useradd --create-home --shell=/bin/bash sysadmin
echo "sysadmin:${SUDOER_PASSWORD}" | chpasswd
echo "sysadmin ALL=(ALL) ALL" > /etc/sudoers.d/sysadmin
echo "sysadmin user created."

# Create .ssh directory and authorized_keys file for sysadmin
echo "Adding public key to sysadmin user's authorized_keys file..."
su - sysadmin -c "mkdir -p /home/sysadmin/.ssh"
su - sysadmin -c "chmod 700 /home/sysadmin/.ssh"
su - sysadmin -c "touch /home/sysadmin/.ssh/authorized_keys"
su - sysadmin -c "chmod 600 /home/sysadmin/.ssh/authorized_keys"
cat /root/.ssh/authorized_keys >> /home/sysadmin/.ssh/authorized_keys
echo "Public keys added to sysadmin user's authorized_keys file."

# Dump ssh config for a ssh client to connect to the server
ip_addr=$( hostname -I | awk '{print $1}' )
ssh_port=$( grep -oP "(?<=Port ).*" /etc/ssh/sshd_config )

# Add default strings if variables are not set
if [ -z "${ip_addr}" ]; then
    ip_addr="<ip_address>"
fi
if [ -z "${ssh_port}" ]; then
    ssh_port="<ssh_port>"
fi

cat <<EOF
Setup complete. You can now connect to the server using the following ssh config:

Host philoch_legacy
  HostName ${ip_addr}
  User sysadmin
  Port ${ssh_port}
  IdentityFile <path_to_your_private_key>
EOF

