# Philosophie.ch Monitoring Stack

Monitors two servers from a single Grafana instance.

## Architecture

```
Assets server                    Main server (monitoring host)
+-----------------+              +-----------------------------------+
| node_exporter   |--SSH tunnel--| Prometheus (host network)         |
| cAdvisor        |              |   scrapes localhost:9109, :8089   |
+-----------------+              |   scrapes localhost:8082 (traefik)|
                                 |   scrapes localhost:9209, :8189   |
                                 |     (tunnel to philo-assets)      |
                                 |                                   |
                                 | Grafana (bridge network)          |
                                 |   reaches Prometheus via          |
                                 |   host.docker.internal:9090       |
                                 |                                   |
                                 | cAdvisor, node_exporter (local)   |
                                 +-----------------------------------+
```

### Components on the monitoring host

- **Prometheus** (`network_mode: host`, port 9090): scrapes all targets via localhost
- **cAdvisor**: per-container metrics; needs Docker socket + privileged mode
- **node_exporter**: host-level CPU, memory, swap, disk metrics
- **Grafana**: dashboards and alerting; access via SSH tunnel

### Components on the assets server

- **cAdvisor**: per-container metrics
- **node_exporter**: host-level metrics

Both bind to `127.0.0.1` only. An SSH tunnel from the monitoring host forwards them to localhost ports there (configured in `.env`).

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
1. Syncs exporter config to the assets server and starts cAdvisor + node_exporter
2. Syncs the monitoring stack to the monitoring host and restarts it
3. Installs and starts the SSH tunnel as a systemd service

### Accessing Grafana

SSH port forward from your local machine:
```bash
ssh -L <grafana-port>:localhost:<grafana-port> <monitor-server>
```
Then open `http://localhost:<grafana-port>`. Login: `admin` / your `GRAFANA_ADMIN_PASSWORD`.

To reset the Grafana admin password:
```bash
ssh <monitor-server> "cd ~/sysadmin-utils/monitoring && docker compose exec grafana grafana cli admin reset-admin-password NEW_PASSWORD"
```

## Dashboards

Two dashboards, auto-provisioned:

**Philosophie.ch Portal** (monitoring host):
- System health: memory %, swap, CPU %, disk %
- Container resources: per-container memory and CPU over time
- Traffic: request rate, error rate by HTTP code, response latency percentiles (from Traefik metrics)

**PhiloAssets Server** (assets server, via SSH tunnel):
- System health: memory %, CPU %, disk %, network traffic
- Container resources: per-container memory and CPU (nginx-proxy-manager, nginx-static, filebrowser)

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

The monitoring host runs an SSH tunnel to the assets server as a systemd service (`monitoring-tunnel`). It forwards the assets server's exporter ports to localhost on the monitoring host so Prometheus can scrape them.

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

Prometheus data and Grafana configuration are stored in Docker volumes (`prometheus_data`, `grafana_data`). They survive container restarts and re-deploys. To reset: `docker compose down -v`.

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

**SMTP alerts not sending:**
- Port 465 uses implicit TLS. `GF_SMTP_STARTTLS_POLICY=NoStartTLS` is required.
- Check logs: `docker logs grafana | grep -i smtp`

## Maintenance

- **Prometheus retention**: 30 days, 2 GB max (whichever hits first)
- **Update images**: edit version tags in `docker-compose.yml`, then `docker compose pull && docker compose up -d`
- **Edit dashboards**: edit in the Grafana UI, then export the JSON and replace the `.json` file
- **Edit alerts**: modify `grafana/provisioning/alerting/rules.yml`, then `docker compose restart grafana`
- **Full restart**: `docker compose down && docker compose up -d`
- **Redeploy everything**: `./deploy.sh`
