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

# Weekly summary on Sundays
day_of_week=$(date +%u)
if [ "${day_of_week}" -eq 7 ] && [ -n "${ALERT_RECIPIENTS}" ]; then
    summary=$(tail -7 "${LOGFILE}")
    printf 'Weekly Backup Summary (PhiloAssets)\n\nLast 7 entries:\n%s\n' "${summary}" \
        | mail -s "Weekly backup summary: PhiloAssets" ${ALERT_RECIPIENTS}
fi
