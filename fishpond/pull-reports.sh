#!/bin/bash -i


# MAIN 
server_path="/home/sandro/dialectica"
output_dir="tasks-output"

echo "=> Cleaning old reports"
rm -rf "${output_dir}"

echo "=> Pulling all output files from the server"
rsync -avzP sandro@fishpond:"${server_path}/${output_dir}" .

if [ $? -ne 0 ]; then
  echo "=> Error: rsync failed. Exiting."
  exit 1
fi

echo "=> Cleanup old reports in the server"
ssh sandro@fishpond "rm -rf ${server_path}/${output_dir}"
echo "=> Pull complete"

