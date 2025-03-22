# Philosophie.ch PLG Monitoring Stack

## Description

This stack is used to monitor the infrastructure of the different servers of the Philosophie.ch association.
It is designed to be completely self-contained and decoupled from the rest of the infrastructure, such that it can be re-used in different servers.
This design also allows us to put it down and back up independently of the rest of the infrastructure of the host machine, without affecting any of the services running on it.

## Stack

- Prometheus: to aggregate metrics from different sources
- cAdvisor: for metrics of the containers
- Node Exporter: for metrics of the host machine
- Loki: for logs
- Grafana: for visualization

## How to use

1. Clone the repository
2. Copy the `.env.example` file to `.env` and fill in the variables
    - The main one you'll need is `MONITORED_NETWORK`, which is the name of the docker network that the stack will monitor
3. Run `docker-compose up -d`
4. Use SSH port forwarding to access Grafana on your local machine. For example:j
    - `ssh -L 3009:localhost:3009 user@host`