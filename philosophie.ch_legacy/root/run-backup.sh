#!/usr/bin/env bash

LOGFILE="/home/sysadmin/rootcron.log"
ALERT_RECIPIENTS="info@philosophie.ch it@philosophie.ch"

/root/dump-assets-db.sh && /root/trigger-backup.sh

if [ $? -eq 0 ]; then
    echo "$(date) Successful backup" >> "${LOGFILE}"
else
    echo "$(date) FAILED backup" >> "${LOGFILE}"
    echo "Backup failed at $(date). Check ${LOGFILE} on the portal server." \
        | mail -s "ALERT: Portal backup failed" ${ALERT_RECIPIENTS}
    exit 1
fi

# Weekly summary on Sundays
day_of_week=$(date +%u)
if [ "${day_of_week}" -eq 7 ]; then
    summary=$(tail -7 "${LOGFILE}")
    printf 'Weekly Backup Summary (Portal)\n\nLast 7 entries:\n%s\n' "${summary}" \
        | mail -s "Weekly backup summary: Portal" ${ALERT_RECIPIENTS}
fi
