# PhiloAssets Server Backup

Automated daily backup of the PhiloAssets file storage to Infomaniak Swiss Backup via rclone.

## What gets backed up

The assets directory (PDFs, images, videos, audio) served by the PhiloAssets system.

## Retention

Two copies are maintained on the remote at all times:

- **latest/**: synced every night at midnight (incremental; only changes are uploaded)
- **weekly/**: full copy refreshed every Sunday, untouched the other 6 days

If a file is accidentally deleted, the weekly copy provides up to 7 days of recovery window.

## Files

| File | Purpose |
|------|---------|
| `.backup.env.example` | Template for all configuration (credentials, paths, recipients) |
| `.backup.env` | Actual config (gitignored, deployed to server) |
| `setup.sh` | One-time server setup: installs rclone, exim4, configures everything, installs cron |
| `backup.sh` | The backup logic (sync latest, refresh weekly on Sundays) |
| `cron-backup.sh` | Cron wrapper: runs backup.sh, logs result, emails on failure |
| `deploy.sh` | Deploys all scripts and config to the server via rsync |

## Setup

1. Copy `.backup.env.example` to `.backup.env` and fill in all values
2. Edit `deploy.sh` and set the `SERVER` variable to match your SSH config
3. Deploy and set up:

```bash
bash deploy.sh
ssh <your-server> 'sudo /root/setup.sh'
```

4. Verify the test email arrived
5. Run a manual backup to confirm:

```bash
ssh <your-server> 'sudo /root/backup.sh'
```

## Updating scripts

After editing any script locally, redeploy with:

```bash
bash deploy.sh
```
