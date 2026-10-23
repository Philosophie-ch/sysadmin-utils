# Philosophie.ch Monitoring Stack

Collects metrics and logs from two servers into a single Grafana instance.

## Architecture

```
Assets server                    Main server (monitoring host)
+-----------------+              +-----------------------------------+
| node_exporter   |--SSH tunnel--| Prometheus (host network)         |
| cAdvisor        |  (forward)   |   scrapes local exporters,        |
|                 |              |   Traefik, and the tunneled       |
|                 |              |   assets exporters                |
|                 |              |                                   |
| Alloy           |--SSH tunnel--| Loki (bridge network)             |
|   proxy log     |  (reverse)   |   receives from both Alloys       |
|   files, docker |              |                                   |
|   containers    |              | Alloy                             |
+-----------------+              |   portal log files, Traefik and   |
                                 |   Alexandria containers           |
                                 |                                   |
                                 | Grafana (bridge network)          |
                                 |   Prometheus via host.docker.     |
                                 |   internal, Loki by service name  |
                                 |                                   |
                                 | cAdvisor, node_exporter (local)   |
                                 +-----------------------------------+
```

### Components on the monitoring host

- **Prometheus** (`network_mode: host`): scrapes all targets via localhost
- **Loki**: log storage, multi-tenant (see [Logs](#logs))
- **Alloy**: ships the portal log files and the Traefik and Alexandria container logs to Loki
- **cAdvisor**: per-container metrics; needs Docker socket + privileged mode
- **node_exporter**: host-level CPU, memory, swap, disk metrics
- **Grafana**: dashboards and alerting; access via SSH tunnel

### Components on the assets server

- **cAdvisor**: per-container metrics
- **node_exporter**: host-level metrics
- **Alloy**: ships the proxy manager's log files and the philoAssets container logs to Loki

All of them bind to `127.0.0.1` only. The SSH tunnel from the monitoring host forwards the assets exporters to localhost ports there, and reverse-forwards a port on the assets server to Loki, so the assets Alloy pushes through it. All ports are set in `.env`.

## Setup

### First time

1. Copy `.env.example` to `.env` and fill in all values
2. If the SMTP password contains special characters (`$`, `!`, `&`, `*`), wrap it in single quotes:
   ```
   SMTP_PASSWORD='password-with-$pecial-chars'
   ```
3. Remove any dead monitoring containers on both servers:
   ```bash
   ssh <monitor-server> "docker rm grafana prometheus promtail loki cadvisor node_exporter 2>/dev/null"
   ssh <assets-server> "docker rm grafana prometheus promtail loki cadvisor node_exporter 2>/dev/null"
   ```
4. Run the deploy script:
   ```bash
   chmod +x deploy.sh philo-assets/ssh-tunnel.sh
   ./deploy.sh
   ```

### Subsequent deploys

```bash
./deploy.sh
```

The deploy script handles everything:
1. Syncs the exporter and Alloy config to the assets server and recreates its containers
2. Syncs the monitoring stack to the monitoring host and restarts it
3. Installs and starts the SSH tunnel as a systemd service

Containers are always recreated, not just restarted when the compose file changes: config files are bind-mounted as single files, and a running container keeps seeing the old file after `rsync` replaces it.

Neither server's `.env` is synced. New variables must be added by hand on each server before deploying; compose stops with an error naming any required one that is missing.

### Accessing Grafana

SSH port forward from your local machine:
```bash
ssh -L <grafana-port>:localhost:<grafana-port> <monitor-server>
```
Then open `http://localhost:<grafana-port>`. Login: `admin` / the current admin password. `GRAFANA_INITIAL_ADMIN_PASSWORD` only sets it when Grafana creates its database; editing it afterwards has no effect.

To change the Grafana admin password:
```bash
ssh <monitor-server> "cd ~/sysadmin-utils/monitoring && docker compose exec grafana grafana cli admin reset-admin-password NEW_PASSWORD"
```

## Dashboards

Three dashboards, auto-provisioned:

**Philosophie.ch Portal** (monitoring host):
- System health: memory %, swap, CPU %, disk %
- Container resources: per-container memory and CPU over time
- Traffic: request rate, error rate by HTTP code, response latency percentiles (from Traefik metrics)

**PhiloAssets Server** (assets server, via SSH tunnel):
- System health: memory %, CPU %, disk %, network traffic
- Container resources: per-container memory and CPU (nginx-proxy-manager, nginx-static, filebrowser)

**Philosophie.ch Logs** (both servers, from Loki), filtered by server, source and a "line contains" text box:
- Volume: lines by level and by source, errors and criticals by source, error totals for the time range
- Lines: latest errors and criticals, latest portal 404s, latest asset proxy 5xx, and all lines for the current filters

## Logs

### Sources

Each stream has a `server` label (from `SERVER_LABEL` in each server's `.env`), a `service_name` label, and a `level` label.

| `service_name` | Server | From |
|----------------|--------|------|
| `portal` | main | `production.log` |
| `portal-errors` | main | `errors_and_warnings.log` |
| `portal-404` | main | `404.log` |
| `traefik`, `alexandria` | main | container logs (allowlist in `alloy/main.alloy`) |
| `proxy-access`, `proxy-error` | assets | proxy manager log files |
| `nginx-static`, `nginx-proxy-manager`, `filebrowser` | assets | container logs (allowlist in `philo-assets/alloy.alloy`) |

Log files are tailed from the end, so a fresh Alloy only ships new lines. Container logs are read from the container's start; anything older than Loki's maximum sample age is rejected (this shows up once as "timestamp too old" errors after a new Alloy starts).

`level` is one of `critical`, `error`, `warn`, `info`, `debug`, `trace`, `unknown`. Sources without a level of their own get one from the HTTP status (5xx error, 4xx warn, else info); lines with neither are `unknown`. Multi-line entries (Rails backtraces) arrive as one entry. Portal lines carry the Rails `request_id` as structured metadata.

### Tenants and retention

Loki runs with multi-tenancy, and Alloy routes each line by level:

- `staff`: everything except debug and trace
- `ops`: debug and trace only (SQL, email dumps, Traefik routing); admin only

Retention is set per tenant in `loki/loki.yml` (default) and `loki/overrides.yml` (`ops`). The Grafana `Loki` datasource reads both tenants at once.

### Redaction

`alloy/lib.alloy` is shared by both servers. It strips terminal colors and redacts values whose name looks like a token, password, secret or API key (query strings, Rails parameter hashes, JSON, SQL binds), plus the `md5` of signed asset URLs. It is a generic safety net only: application-specific leaks are fixed in the application, not with new rules here.

### Querying

In Grafana: **Explore**, datasource `Loki`, or the Logs dashboard. Examples:

```logql
{service_name="portal", level=~"error|critical"}
{service_name="portal"} | request_id="<uuid>"
{service_name="traefik"} |= "502"
sum by (service_name) (count_over_time({level="error"}[5m]))
```

From a shell, query the API on the monitoring host with the tenant header (`staff`, `ops`, or `staff|ops`):

```bash
ssh <monitor-server> "curl -s -G -H 'X-Scope-OrgID: staff' localhost:<loki-port>/loki/api/v1/query_range \
  --data-urlencode 'query={service_name=\"portal\", level=\"error\"}' --data-urlencode 'since=1h' --data-urlencode 'limit=50'"
```

## Alerts

Alerts are provisioned for the monitoring host and send email. The recipient is configured in `grafana/provisioning/alerting/contactpoints.yml`.

| Alert | Threshold | Sustained for | Severity |
|-------|-----------|---------------|----------|
| Memory usage | > 90% | 10 min | critical |
| CPU usage | > 95% | 10 min | critical |
| Swap usage | > 1 GiB | 10 min | warning |
| Disk usage | > 90% | 5 min | warning |

Repeat interval: 4 hours.

## SSH Tunnel

The monitoring host runs an SSH tunnel to the assets server as a systemd service (`monitoring-tunnel`). It forwards the assets server's exporter ports to localhost on the monitoring host so Prometheus can scrape them, and reverse-forwards a localhost port on the assets server to Loki so the assets Alloy can push logs. While the tunnel is down, the assets Alloy buffers and retries.

The tunnel reconnects automatically on failure (via `ServerAliveInterval` + systemd `Restart=always`).

Check tunnel status:
```bash
ssh <monitor-server> "sudo systemctl status monitoring-tunnel"
```

Restart the tunnel:
```bash
ssh <monitor-server> "sudo systemctl restart monitoring-tunnel"
```

## Traefik Metrics

Traefik must expose a Prometheus metrics endpoint for the traffic panels to work. This requires Traefik CLI args:

```
--entryPoints.metrics.address=:8082
--metrics.prometheus=true
--metrics.prometheus.entryPoint=metrics
```

These are configured in the portal's Kamal deploy config. Changing Traefik args requires `kamal traefik reboot` (not `docker restart`; a restart reuses the old args). A reboot causes a brief (~2 second) interruption.

## Data Persistence

Prometheus data, Grafana configuration and Loki data are stored in Docker volumes (`prometheus_data`, `grafana_data`, `loki_data`). Each Alloy keeps its read positions in `alloy_data`, so a restart continues where it stopped instead of re-sending. They survive container restarts and re-deploys. To reset: `docker compose down -v`.

## Troubleshooting

**Container panels show "No data":**
- Check cAdvisor can talk to Docker: `docker logs cadvisor | grep 'docker container factory'`. Must say "successfully". If "failed" with API version mismatch, upgrade cAdvisor. v0.60.5+ works with Docker Engine v29+.

**PhiloAssets panels show "No data":**
- Check the SSH tunnel: `sudo systemctl status monitoring-tunnel`
- Verify Prometheus can reach the tunneled ports: `curl http://localhost:9209/metrics` and `curl http://localhost:8189/metrics`
- Check Prometheus targets: `curl -s http://localhost:9090/api/v1/targets`

**Traefik panels show "No data":**
- Verify: `curl http://localhost:8082/metrics`
- If connection refused: Traefik args haven't been applied. Use `kamal traefik reboot`.
- Check Prometheus targets: `curl http://localhost:9090/api/v1/targets`

**ghcr.io image pull "denied":**
- Run `docker logout ghcr.io`, then pull again.

**Grafana datasource error:**
- Grafana reaches Prometheus via `host.docker.internal:9090`. Verify: `curl http://localhost:9090/-/healthy`

**Logs missing from a source:**
- Check Alloy's errors on that server: `docker logs --since 10m alloy 2>&1 | grep -E 'level=(error|warn)'`. Its UI (component health) is on `localhost:<alloy-port>` on each server.
- Assets logs: the tunnel must be up; `curl http://localhost:<loki-push-port>/ready` on the assets server must answer through the reverse forward.
- "could not transfer logs ... invalid character '\x00'" for a container: its Docker log file is corrupt (`docker logs <name>` fails too), and Docker re-parses the whole file on every retry, which can keep `dockerd` busy. Recreate the container to start a fresh log file.

**SMTP alerts not sending:**
- Port 465 uses implicit TLS. `GF_SMTP_STARTTLS_POLICY=NoStartTLS` is required.
- Check logs: `docker logs grafana | grep -i smtp`

## Maintenance

- **Prometheus retention**: 30 days, 2 GB max (whichever hits first)
- **Loki retention**: per tenant, see [Tenants and retention](#tenants-and-retention)
- **Edit log pipelines**: `alloy/lib.alloy` (shared), `alloy/main.alloy`, `philo-assets/alloy.alloy`, then `./deploy.sh`
- **Update images**: edit version tags in `docker-compose.yml`, then `docker compose pull && docker compose up -d`
- **Edit dashboards**: edit in the Grafana UI, then export the JSON and replace the `.json` file
- **Edit alerts**: modify `grafana/provisioning/alerting/rules.yml`, then `docker compose restart grafana`
- **Full restart**: `docker compose down && docker compose up -d`
- **Redeploy everything**: `./deploy.sh`
