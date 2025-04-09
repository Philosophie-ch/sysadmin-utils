#!/usr/bin/env bash

ssh -t sandro@fishpond 'bash -lc "cd dialectica && RAILS_ENV=production rails console"'

