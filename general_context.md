# Philosophie.ch Sysadmin Utils — General Context

Overview of all sysadmin tooling for the Philosophie.ch association. For implementation detail on any sub-project, read the specific guide listed in the Guide Index at the bottom.

## Repository Overview

Scripts and utilities organized by target system. Each top-level directory corresponds to tools for a specific server or product.

| Directory | Target System | Purpose |
|-----------|--------------|---------|
| `philosophie.ch_legacy/` | Legacy portal server | Portal admin scripts, bulk data operations, asset management, server tasks |
| `alexandria/` | Alexandria bibliography server | Import pipeline, prod ops scripts, DB backup |
| `copyright/` | Local workstation | Image copyright detection and metadata analysis |
| `fishpond/` | Fishpond server (Dialectica) | Task push/pull scripts for Dialectica content management |
| `dotfiles/` | Any machine | Shell configuration templates (zsh, vim, aliases) |
| `monitoring/` | Any server | PLG (Prometheus + Loki + Grafana) monitoring stack |

## philosophie.ch_legacy/

Main ops tooling for the Philosophie.ch legacy portal. This is the most used area of the repo.

### sysadmin/portal-tasks/

CSV-driven bulk content scripts that run inside the portal's Rails Docker container. Each script processes a CSV file where every row has a `_request` column (`POST`, `UPDATE`, `GET`, `DELETE`, etc.) and generates a timestamped CSV report.

Entry-point scripts:

| Script | Entity | Purpose |
|--------|--------|---------|
| `pages.rb` | `Alchemy::Page` | Page CRUD: tags, assets, elements, authors, metadata |
| `profiles.rb` | `Alchemy::User` / `Profile` | User account management |
| `publications.rb` | `Publication` | Academic publications with author relationships |
| `journals.rb` | `Journal` | Journal management |
| `publishers.rb` | `Publisher` | Publisher management |
| `themetags.rb` | `Topic` | Topic/themetag management |
| `events.rb` | `Event` | Event management |
| `news.rb` | Various | Read-only overview report |
| `links.rb` | Pages | Link extraction + HTTP validation |
| `export_pages.rb` | `Alchemy::Page` | Fast bulk GET; supports merge mode with Google Sheets |
| `export_profiles.rb` | `Alchemy::User` | Fast bulk GET; supports merge mode |
| `bulk_image_migration.rb` | Pages + Profiles | Scan/migrate portal-managed images to asset server |
| `bulk_media_migration.rb` | Pages | Scan/migrate audio/video/pdf to asset server |

Library files live in `portal-tasks/lib/` — see `portal-tasks/docs/portal_tasks_context.md` for full function-level documentation.

### sysadmin/ infrastructure scripts

| Script | Purpose |
|--------|---------|
| `push-tasks.sh` | Rsync `portal-tasks/` to server, then `docker cp` into Rails container |
| `pull-reports.sh` | `docker cp` reports out of container, rsync to local machine |
| `rails-console.sh` | Open Rails console in running container |
| `ssh-rails-console.sh` | Open Rails console over SSH |
| `container-console.sh` | Direct shell access to container |
| `ssh-container-console.sh` | Shell access to container over SSH |
| `dev-pushtasks.sh` | Dev environment variant of push-tasks |
| `dev-pullreports.sh` | Dev environment variant of pull-reports |

Environment config: `.env` and `.env.example` in `sysadmin/` — contains `SERVER_USER_AT_IP`, `SERVER_PORT`, `SERVER_CONTAINER_BASENAME`, `LOCAL_REPORTS_PATH`.

### root/ — server-level scripts

| Script | Purpose |
|--------|---------|
| `trigger-backup.sh` | Trigger server-side backup |
| `dump-assets-db.sh` | Dump assets database |
| `setup.sh` | One-time server setup |

Config: `.backup.env` and `.backup.env.example`.

### Other subdirectories

| Path | Purpose |
|------|---------|
| `sysadmin/rails-utils/` | Ad-hoc Rails console utility scripts |
| `sysadmin/local-portal-tasks/` | Python scripts for local link/data processing |
| `sysadmin/system-tasks/` | System-level tasks (cache cleanup, app data import) |

## copyright/

Python-based image copyright detection tooling. Uses Google Vision API and perceptual image hashing to detect potentially unauthorized images.

Key files:

| File | Purpose |
|------|---------|
| `check_aggregator.py` | Orchestrates all copyright checks |
| `check_google_vision.py` | Google Vision API integration |
| `check_image_hashes.py` | Perceptual hash matching |
| `check_image_metadata.py` | EXIF/metadata extraction |
| `base_types.py` | Shared type definitions (`ExifReport`, `ImageReport`) |

Dependencies: see `requirements.txt` at repo root. Type checking: mypy strict mode (see `pyproject.toml`).

## fishpond/

Scripts for managing tasks on the Fishpond server (Dialectica content). Follows the same push/pull pattern as portal-tasks.

| Script | Purpose |
|--------|---------|
| `push-tasks.sh` | Rsync `tasks/` dir to Fishpond server |
| `pull-reports.sh` | Pull output files from server |
| `ssh-rails-console.sh` | Open Rails console on Fishpond over SSH |

Task scripts live in `tasks/`. Output lands in `tasks-output/`.

## dotfiles/

Shell configuration templates for provisioning developer machines.

| File | Purpose |
|------|---------|
| `zshrc_template` | Zsh configuration template |
| `vimrc_template` | Vim configuration template |
| `shell_aliases` | Shared shell alias definitions |

## monitoring/

Self-contained PLG (Prometheus + Loki + Grafana) monitoring stack, deployed via Docker Compose. See `monitoring/README.md` for full setup instructions and SSH tunnel access.

Stack: Prometheus, cAdvisor, Node Exporter, Loki, Promtail, Grafana.

## alexandria/

Tools for the Alexandria bibliography system — a Rust API that manages 200K+ bibliographic entries for Philosophie.ch. Three sub-areas:

### alexandria/dev/ — Bulk import pipeline (local dev)

Converts portal Google Sheet exports into Alexandria's import format and runs a full reimport against a local Alexandria dev instance.

| File | Purpose |
|------|---------|
| `convert.py` | Read portal CSVs from `ALEXANDRIA_DATA_DIR` → write Alexandria-format CSVs |
| `import_all.sh` | 7-step pipeline: convert → import authors/journals/publishers → import entities → validate → import bibitems → LaTeX→Unicode → generate report |
| `generate_report.py` | Cross-reference JSON results back to source CSV rows; write per-error `.txt` reports + `SUMMARY.txt` |

Source CSVs required in `ALEXANDRIA_DATA_DIR`:
- `portal data - profiles.csv`, `portal data - biblio profiles.csv` → authors
- `portal data - journals.csv`, `portal data - publishers.csv`
- `biblio-v11-table.csv` — full bibliography
- `author_name_variants.csv` — hand-maintained mononym/variant mappings

`.env` needs: `ALEXANDRIA_API_URL`, `ALEXANDRIA_API_KEY`, `ALEXANDRIA_DATA_DIR`, `ALEXANDRIA_DB_CONTAINER`, `ALEXANDRIA_CORPUS_PATH`, `ALEXANDRIA_NEXUS_DIR`

Reports land in `$ALEXANDRIA_DATA_DIR/reports/YYYYMMDD_HHMMSS/`. The most useful file is `SUMMARY.txt`.

### alexandria/sysadmin/ — Prod operations

Direct API/SSH scripts for operating the production Alexandria server. All require `.env` (see `.env.example`).

| Script | Purpose |
|--------|---------|
| `tunnel.sh` | Open SSH tunnel: `localhost:8080` → prod:8080 (Ctrl-C to close) |
| `health.sh` | Check Alexandria is up |
| `validate-csv.sh file.csv` | Validate a bibliography CSV before importing |
| `import-csv.sh file.csv` | Two-step import: entities first, then bibitems (upsert) |
| `export.sh <entity> [out]` | Export entity to CSV (authors/journals/bibitems/etc.) |
| `logs.sh [--tail N]` | Stream prod container logs via SSH |
| `data-version.sh` | Fetch current data version from prod |
| `corpus-rebuild.sh` | Reimport from local corpus clone (wipe + bulk COPY) |

`lib.sh` is sourced by all scripts — reads `.tunnel-port` written by `tunnel.sh` and prints a target banner (prod vs local dev).

`.env` needs: `SERVER_USER_AT_IP`, `SERVER_PORT`, `ALEXANDRIA_API_KEY`, `ALEXANDRIA_LOCAL_PORT`, `ALEXANDRIA_CORPUS_PATH`

### alexandria/root/ — Server-side DB backup

| File | Purpose |
|------|---------|
| `dump-alexandria-db.sh` | Daily PostgreSQL dump script |
| `crontab` | Cron schedule |

Config lives in `~/.alexandria-backup.env` on the server.

## Common Workflow: Alexandria Corpus Update

End-to-end flow when the bibliography needs updating. Triggered when the user places an updated bibliography CSV (name varies — user specifies) and/or updated portal entity CSVs in `ALEXANDRIA_DATA_DIR`.

### Step 1 — Dev import

From `alexandria/dev/` with `.env` configured:

```bash
python3 convert.py    # portal CSVs → authors_pr.csv, authors_bp.csv, journals.csv, publishers.csv
./import_all.sh       # full 7-step pipeline (convert → authors → journals/publishers → entities → validate → import-full-csv → LaTeX→Unicode → report)
```

`import_all.sh` uses `POST /api/v1/admin/import-full-csv` (upsert + delete stale) against the local dev instance. Reports land in `$ALEXANDRIA_DATA_DIR/reports/<timestamp>/`. **The most useful file is `SUMMARY.txt`.**

### Step 2 — Validate (user)

The agent shows `SUMMARY.txt`. The user reviews it, fixes issues in the source spreadsheets (missing authors, mismatched journal names, parse errors, etc.), and re-runs Step 1 as many times as needed. The user decides when the import is clean enough to proceed.

### Step 3 — Snapshot → update corpus

```bash
"$ALEXANDRIA_CORPUS_PATH/scripts/update-corpus-from-snapshot.sh" "$ALEXANDRIA_API_URL" "$ALEXANDRIA_API_KEY"
```

Calls `POST /api/v1/admin/snapshot` on the dev instance, unpacks the ZIP, and replaces `data/` in the `alexandria-corpus` repo. Review with `git -C "$ALEXANDRIA_CORPUS_PATH" diff --stat`.

### Step 4 — Release to prod

1. Bump `data_version.yml` (version + description) in `alexandria-corpus`
2. Open a PR, review the diff, merge to `main`
3. Publish a GitHub release — CI SSHes into prod and runs the bulk-COPY reimport

For an on-demand prod push (outside of a release):
```bash
cd alexandria/sysadmin && ./tunnel.sh     # Terminal 1 — keep open
./corpus-rebuild.sh                       # Terminal 2
```

Use `/update-alexandria-corpus` for a guided interactive walkthrough of this full chain.

---

## Common Workflow: Portal Tasks

The standard workflow for running portal content operations:

1. Edit task scripts or CSV files locally in `philosophie.ch_legacy/sysadmin/portal-tasks/`
2. Run `./push-tasks.sh` from `philosophie.ch_legacy/sysadmin/` to sync to server and inject into Rails container
3. On the production server (inside Rails container), run:
   ```bash
   bundle exec rails runner portal-tasks/[script].rb [csv_file] [log_level]
   ```
   Log levels: `debug`, `info`, `warn`, `error`
4. Run `./pull-reports.sh` to retrieve generated CSV reports

Reports are timestamped and land in the configured `LOCAL_REPORTS_PATH`.

## Guide Index

| Guide | Path | When to Read |
|-------|------|--------------|
| Portal Tasks Context | `philosophie.ch_legacy/sysadmin/portal-tasks/docs/portal_tasks_context.md` | Working with CSV-driven bulk scripts |
| Monitoring Stack | `monitoring/README.md` | Setting up or managing PLG monitoring |
| Alexandria API / Import-Export | `/home/alebg/philosophie-ch/bibliography/alexandria-nexus/docs/IMPORT_EXPORT.md` | Working with Alexandria dev tools or sysadmin scripts |
| Alexandria Architecture | `/home/alebg/philosophie-ch/bibliography/alexandria-nexus/docs/ARCHITECTURE.md` | Understanding the Alexandria backend (Rust, hexagonal) |
| Alexandria CLAUDE.md | `/home/alebg/philosophie-ch/bibliography/alexandria-nexus/.claude/CLAUDE.md` | Full Alexandria dev context (build, test, code generation) |
