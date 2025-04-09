#!/bin/bash -i

# MAIN
server_path="/home/sandro/dialectica"
tasks_dir="tasks"

echo "=> Cleaning old tasks"
ssh sandro@fishpond "rm -rf ${server_path}/${tasks_dir}"

echo "=> Pushing tasks to the server"
rsync -avzP tasks sandro@fishpond:"${server_path}"

echo "=> Push complete"

