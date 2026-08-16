#!/bin/bash
set -euo pipefail

SSH_KEY="$HOME/.ssh/id_rsaPhilippBlum"
SSH_USER="deploy"
SERVER="159.65.120.231"
server_path="/home/deploy"
tasks_dir="tasks"

echo "=> Cleaning old tasks"
ssh -i "$SSH_KEY" "${SSH_USER}@${SERVER}" "rm -rf ${server_path}/${tasks_dir}"

echo "=> Pushing tasks to the server"
rsync -avzP -e "ssh -i ${SSH_KEY}" tasks "${SSH_USER}@${SERVER}:${server_path}"

echo "=> Push complete"

