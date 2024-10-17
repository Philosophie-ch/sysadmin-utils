#!/bin/bash

rails_container=$(docker ps --format '{{.Names}}' | grep "${1}")

docker exec -ti "$rails_container" bash -c "cd /rails && bundle exec rails console"
