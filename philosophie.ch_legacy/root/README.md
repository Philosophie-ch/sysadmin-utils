# Portal Server Backup

Automated daily backup of the philosophie.ch legacy portal to Infomaniak Swiss Backup via rclone.

## What gets backed up

- PostgreSQL database (full dump + data-only dump)
- Rails assets (storage, uploads, public/system, public/pictures)

## How it works

A single cron job (`run-backup.sh`) runs at midnight UTC and orchestrates:

1. **dump-assets-db.sh**: rsyncs Rails assets and dumps the database from the Docker container into a local backup directory. Exits non-zero if either dump fails.
2. **trigger-backup.sh**: uploads DB dumps to a dated remote directory (`db/YYYY-MM-DD/`), syncs assets to a separate remote directory (`assets/`), then prunes old snapshots according to the retention policy.
3. **run-backup.sh**: runs both scripts, logs the result to `rootcron.log`, and sends an email alert on failure.

## Retention policy

- 1 snapshot per day for the past 7 days
- 1 per week for the past 3 months
- 1 per month for the past 6 months
- Older snapshots are deleted automatically

## Configuration

All config lives in `/root/.backup.env` on the server. See `.backup.env.example` for the required variables.

rclone must be configured with the Swift backend in `/root/.config/rclone/rclone.conf`.

Email alerts are sent via exim4 configured as a smarthost relay through Infomaniak SMTP.

## Deployment

Edit the `SERVER` variable in `deploy.sh` to match your SSH config, then run:

```bash
bash deploy.sh
```
