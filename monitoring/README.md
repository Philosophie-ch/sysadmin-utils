# Philosophie.ch Monitoring Stack

## Stack

- **Prometheus**: metrics storage and query (scrapes node_exporter, cAdvisor, Traefik)
- **cAdvisor**: per-container CPU, memory, network, disk I/O metrics
- **node_exporter**: host-level CPU, memory, swap, disk metrics
- **Grafana**: dashboards and alerting

All ports are bound to `127.0.0.1` only; access Grafana via SSH tunnel.

## Setup

1. Copy `.env.example` to `.env` and fill in the values:
   - `GRAFANA_ADMIN_PASSWORD`: pick a strong password
   - `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`: SMTP credentials for alert emails
   - `SMTP_FROM`: sender address for alert emails (default: `monitoring@philosophie.ch`)

2. Start the stack:
   ```bash
   docker compose up -d
   ```

3. Access Grafana via SSH port forwarding:
   ```bash
   ssh -L 3009:localhost:3009 <user>@<server>
   ```
   Then open `http://localhost:3009` in your browser. Login: `admin` / your `GRAFANA_ADMIN_PASSWORD`.

## Dashboard

One custom dashboard: **Philosophie.ch Portal**

- **System Health**: memory %, swap usage, CPU %, disk %
- **Container Resources**: per-container memory and CPU over time
- **Traffic**: request rate, error rate by HTTP code, response latency percentiles (p50/p95/p99)

## Alerts

Alerts are provisioned automatically. The default recipient is configured in `grafana/provisioning/alerting/contactpoints.yml`.

| Alert | Threshold | Sustained for | Severity |
|-------|-----------|---------------|----------|
| Memory usage | > 90% | 10 min | critical |
| CPU usage | > 95% | 10 min | critical |
| Swap usage | > 1 GiB | 10 min | warning |
| Disk usage | > 90% | 5 min | warning |

Repeat interval: 4 hours.

## Traefik metrics

Traefik must expose a Prometheus metrics endpoint on port 8082 (localhost only) for the traffic panels to work. This is a Traefik configuration change, not part of this stack. See `prometheus.yml` for the scrape target.

## Data persistence

Prometheus data and Grafana configuration are stored in Docker volumes (`prometheus_data`, `grafana_data`). They survive container restarts and re-deploys. To reset: `docker compose down -v`.

## Maintenance

- **Prometheus retention**: 30 days, 2 GB max (whichever hits first)
- **Update images**: edit version tags in `docker-compose.yml`, then `docker compose pull && docker compose up -d`
- **Edit dashboards**: edit in the Grafana UI, then export the JSON and replace `philosophie-ch-portal.json`
- **Edit alerts**: modify `grafana/provisioning/alerting/rules.yml`, then `docker compose restart grafana`
