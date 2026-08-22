#!/usr/bin/env bash

source "${HOME}/.backup.env"

LOGFILE="/home/sysadmin/rootcron.log"
ALERT_RECIPIENTS="${ALERT_RECIPIENTS:-}"

/root/backup.sh

if [ $? -eq 0 ]; then
    echo "$(date) Successful assets backup" >> "${LOGFILE}"
else
    echo "$(date) FAILED assets backup" >> "${LOGFILE}"
    if [ -n "${ALERT_RECIPIENTS}" ]; then
        echo "PhiloAssets backup failed at $(date). Check ${LOGFILE} on the assets server." \
            | mail -s "ALERT: PhiloAssets backup failed" ${ALERT_RECIPIENTS}
    fi
    exit 1
fi
