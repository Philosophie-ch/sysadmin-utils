#!/bin/bash
set -euo pipefail

SSH_KEY="$HOME/.ssh/id_rsaPhilippBlum"
SSH_USER="deploy"
SERVER="159.65.120.231"
server_path="/home/deploy"
output_dir="tasks-output"

echo "=> Cleaning old reports"
rm -rf "${output_dir}"

echo "=> Pulling all output files from the server"
rsync -avzP -e "ssh -i ${SSH_KEY}" "${SSH_USER}@${SERVER}:${server_path}/${output_dir}" .

echo "=> Cleanup old reports in the server"
ssh -i "$SSH_KEY" "${SSH_USER}@${SERVER}" "rm -rf ${server_path}/${output_dir}"
echo "=> Pull complete"

