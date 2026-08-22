#!/usr/bin/env bash

LOGFILE="/home/sysadmin/rootcron.log"
ALERT_RECIPIENTS="info@philosophie.ch it@philosophie.ch"

/root/dump-assets-db.sh && /root/trigger-backup.sh

if [ $? -eq 0 ]; then
    echo "$(date) Successful backup" >> "${LOGFILE}"
else
    echo "$(date) FAILED backup" >> "${LOGFILE}"
    echo "Backup failed at $(date). Check ${LOGFILE} on philo-000." \
        | mail -s "ALERT: philosophie.ch backup failed" ${ALERT_RECIPIENTS}
fi
