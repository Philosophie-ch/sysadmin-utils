# Philosophie.ch Monitoring Stack

## Stack

- **Prometheus** (`network_mode: host`): metrics storage and query; scrapes node_exporter, cAdvisor, and Traefik
- **cAdvisor**: per-container CPU, memory, network, disk I/O metrics
- **node_exporter**: host-level CPU, memory, swap, disk metrics
- **Grafana**: dashboards and alerting

Grafana, cAdvisor, and node_exporter bind their ports to `127.0.0.1` only. Prometheus runs on the host network (port 9090). Access Grafana via SSH tunnel.

## Architecture

Prometheus uses `network_mode: host` so it can reach all scrape targets via `localhost`:
- `localhost:9109` for node_exporter
- `localhost:8089` for cAdvisor
- `localhost:8082` for Traefik metrics

Grafana runs on the `monitoring` bridge network and reaches Prometheus via `host.docker.internal:9090` (mapped through `extra_hosts`).

cAdvisor needs `privileged: true` and access to `/var/run/docker.sock` to resolve Docker container names. Without the Docker socket, metrics exist but lack the `name` label and container panels show "No data".

## Setup

1. Copy `.env.example` to `.env` and fill in the values:
   - `GRAFANA_ADMIN_PASSWORD`: pick a strong password
   - `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`: SMTP credentials for alert emails
   - `SMTP_FROM`: sender address for alert emails (default: `monitoring@philosophie.ch`)

2. If the SMTP password contains special characters (`$`, `!`, `&`, `*`), wrap it in single quotes in `.env`:
   ```
   SMTP_PASSWORD='password-with-$pecial-chars'
   ```

3. Start the stack:
   ```bash
   docker compose up -d
   ```

4. Access Grafana via SSH port forwarding:
   ```bash
   ssh -L 3009:localhost:3009 <user>@<server>
   ```
   Then open `http://localhost:3009` in your browser. Login: `admin` / your `GRAFANA_ADMIN_PASSWORD`.

5. To reset the Grafana admin password:
   ```bash
   docker compose exec grafana grafana cli admin reset-admin-password NEW_PASSWORD
   ```

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

Traefik must expose a Prometheus metrics endpoint on port 8082 for the traffic panels to work. This requires three Traefik CLI args:

```
--entryPoints.metrics.address=:8082
--metrics.prometheus=true
--metrics.prometheus.entryPoint=metrics
```

And the port must be published: `8082:8082` (or `127.0.0.1:8082:8082`).

These are configured in the portal's Kamal deploy config. Changing Traefik args requires `kamal traefik reboot` (not just `docker restart`; a restart reuses the old args). A reboot causes a brief (~2 second) interruption.

## Data persistence

Prometheus data and Grafana configuration are stored in Docker volumes (`prometheus_data`, `grafana_data`). They survive container restarts and re-deploys. To reset: `docker compose down -v`.

## Troubleshooting

**Container panels show "No data":**
- Check cAdvisor can talk to Docker: `docker logs cadvisor | grep 'docker container factory'`. It must say "Registration of the docker container factory successfully". If it says "failed", the Docker API version is incompatible; upgrade cAdvisor.
- cAdvisor v0.49.x is incompatible with Docker Engine v29+ (API v1.44 minimum). Use v0.60.5+.

**Traefik panels show "No data":**
- Verify the metrics endpoint responds: `curl http://localhost:8082/metrics`
- If connection refused: Traefik args haven't been applied. Use `kamal traefik reboot`, not `docker restart`.
- Check Prometheus target status: `curl http://localhost:9090/api/v1/targets`

**ghcr.io image pull "denied":**
- Run `docker logout ghcr.io` on the server, then pull again. Stale credentials block anonymous pulls from the GitHub Container Registry.

**Grafana shows "datasource not found":**
- Grafana reaches Prometheus via `host.docker.internal:9090`. Verify `extra_hosts` is set on the Grafana container and Prometheus is listening: `curl http://localhost:9090/-/healthy`

**SMTP alerts not sending:**
- Port 465 uses implicit TLS, not STARTTLS. `GF_SMTP_STARTTLS_POLICY=NoStartTLS` is required in the Grafana environment.
- Check Grafana logs: `docker logs grafana | grep -i smtp`

## Maintenance

- **Prometheus retention**: 30 days, 2 GB max (whichever hits first)
- **Update images**: edit version tags in `docker-compose.yml`, then `docker compose pull && docker compose up -d`
- **Edit dashboards**: edit in the Grafana UI, then export the JSON and replace `philosophie-ch-portal.json`
- **Edit alerts**: modify `grafana/provisioning/alerting/rules.yml`, then `docker compose restart grafana`
- **Full restart**: `docker compose down && docker compose up -d`
