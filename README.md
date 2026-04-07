# Perfana Demo

## Overview

The Perfana demo environment lets you explore all Perfana features using Docker Compose. It provides a realistic performance testing environment including load testing, metrics, distributed tracing, continuous profiling, and automated regression detection.

## Prerequisites

* [Docker](https://docs.docker.com/get-started/) with Docker Compose
* Minimum **8 GB RAM** allocated to Docker (16 GB recommended)
* `jq` installed (for the init script)

## Getting Started

Clone the repository:

```sh
git clone https://github.com/perfana/perfana-demo.git
cd perfana-demo
```

Run the initialization script (first time only):

```sh
./init-demo.sh
```

This starts all services, runs database migrations, configures integrations (Grafana, Tempo, Pyroscope), creates API keys, and runs an initial set of baseline load tests.

### Dynatrace Mock (optional)

To also start WireMock-based Dynatrace API stubs (SaaS and Managed flavours), pass the `--dynatrace-mock` flag:

```sh
./init-demo.sh --dynatrace-mock
```

This starts two additional containers and automatically registers the Dynatrace instance and entity mappings (HOST + SERVICE) in Perfana.

## Services

| Container               | Description                              | Local port |
|:------------------------|:-----------------------------------------|:-----------|
| perfana-web             | Perfana UI (Next.js)                     | 4000       |
| perfana-api             | Perfana API (NestJS)                     | 3001       |
| perfana-worker          | Background job processor (BullMQ)        | —          |
| perfana-grafana-sync    | Grafana dashboard sync service           | —          |
| perfana-report          | PDF report generation                    | —          |
| keycloak                | Authentication server                    | 8080       |
| postgres                | TimescaleDB — Perfana data store         | 5432       |
| redis                   | Job queue                                | 6379       |
| grafana                 | Grafana dashboards                       | 3000       |
| prometheus              | Metrics collection                       | 9090       |
| alertmanager            | Alert routing                            | 9093       |
| influxdb                | Time-series metrics (JMeter results)     | 8086       |
| tempo                   | Distributed tracing backend              | 3200       |
| pyroscope               | Continuous profiling                     | 4040       |
| loki                    | Log aggregation                          | 3100       |
| telegraf                | Docker metrics collector                 | —          |
| afterburner-fe          | Spring Boot test application (frontend)  | 8090       |
| afterburner-be          | Spring Boot test application (backend)   | —          |
| mariadb                 | Database used by afterburner             | 3306       |
| wiremock                | HTTP mock server                         | 8060       |
| dynatrace-mock          | Dynatrace SaaS API stub (optional)       | 8061       |
| dynatrace-managed-mock  | Dynatrace Managed API stub (optional)    | 8062       |

## Day-to-day Commands

```sh
# Start all existing containers (after init)
./start.sh

# Start infrastructure only (for local Perfana development)
./start-infra.sh

# Stop all containers
./stop.sh

# Remove all containers and volumes (data will be lost)
./clean.sh
```

## Running Load Tests

```sh
# Baseline test (establishes performance benchmarks)
./deploy-and-test-jmeter.sh baseline

# Test with CPU performance issue
./deploy-and-test-jmeter.sh cpu

# Test with connection pool issue
./deploy-and-test-jmeter.sh pool

# Test with slow backend calls issue
./deploy-and-test-jmeter.sh backend
```

Run a baseline first, then disable baseline mode in Perfana and run one of the issue variants to trigger automatic regression detection.

## Detecting Regressions

1. Run `./deploy-and-test-jmeter.sh baseline` (done automatically by `init-demo.sh`)
2. In Perfana, disable **Baseline mode** for the `afterburner` system under test
3. Run `./deploy-and-test-jmeter.sh cpu` (or `pool` / `backend`)
4. Perfana automatically compares against the baseline and flags regressions

## Exploring the Environment

### Perfana

URL: [http://localhost:4000](http://localhost:4000)

| User | Password | Role |
|:-----|:---------|:-----|
| admin@perfana.io | Test@1234 | Admin |
| daniel@perfana.io | perfana | User |
| dylan@perfana.io | perfana | User |

### Grafana

URL: [http://localhost:3000](http://localhost:3000) — user: `perfana`, password: `perfana`

### Keycloak

URL: [http://localhost:8080](http://localhost:8080) — user: `admin`, password: `admin`

## Keeping Up to Date

```sh
git pull && docker compose pull
```

## Credits

The employee database used in this demo is derived from [datacharmer/test_db](https://github.com/datacharmer/test_db).
