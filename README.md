# Perfana on RHEL 9 with Podman

A **production** Perfana deployment for **Red Hat Enterprise Linux 9**, running on **Podman**
with Compose. It deploys the core Perfana platform; **Grafana is optional** and sits behind a
compose profile.

> **Full instructions: [INSTALL.md](INSTALL.md).** This README is the short version.

## Components

**Core** (always started): `postgres`, `valkey`, `keycloak`, `perfana-migration`, `perfana-api`,
`perfana-web`, `perfana-worker`, `perfana-report`, `docker-socket-proxy`, and the
`valkey-monitor` / `docker-monitor` samplers.

**Optional**, via `COMPOSE_PROFILES` in `.env`:

| Profile | Adds |
|---|---|
| `grafana` | `grafana` + `perfana-grafana-sync` — metric panels, dashboard snapshots in reports, dashboard sync. |
| `pgbouncer` | `pgbouncer` — connection pooler for load generators. |

Without the `grafana` profile Perfana still runs tests, stores results, shows transaction and
request statistics and trends, evaluates requirements and benchmarks, runs ADAPT regression
analysis and produces HTML/PDF reports on all of that. What it cannot do is show panels sourced
from a Grafana data source, or embed dashboard snapshots in a report.

## Quick start

Assuming Podman, Compose v2 and the Podman socket are set up per [INSTALL.md](INSTALL.md):

```bash
cp .env.example .env       # then edit: set the secrets, PODMAN_SOCKET, COMPOSE_PROFILES
./start.sh                 # start DB, migrate, start Keycloak + Perfana services
./bootstrap.sh             # first run only: org, admin, provisioning, API key
```

Browse to `http://localhost:4001` (`PERFANA_WEB_PORT`) on the server.

To add Grafana later, set `COMPOSE_PROFILES=grafana` in `.env` and re-run `./start.sh` and
`./bootstrap.sh`. Nothing needs reinstalling.

## Container runtime

Every script defaults to Podman and can be pointed at Docker without editing:

```bash
CONTAINER_CLI=docker COMPOSE="docker compose" ./start.sh
```

All bind mounts carry a `:z` SELinux label, so the stack runs with SELinux enforcing.

## Scripts

| Script | Purpose |
|---|---|
| `start.sh` | Start the stack in dependency order (DB → migrate → Keycloak → services). |
| `stop.sh` | Stop containers (`--volumes` to also delete data — destructive). |
| `update.sh` | Pull pinned images, re-run migrations, recreate services. |
| `bootstrap.sh` | One-time first-run integration setup. Skips Grafana when that profile is off. |
| `scripts/mint-pgbouncer-userlist.sh` | Write `pgbouncer/userlist.txt` from `POSTGRES_PASSWORD`. |
| `scripts/setup-db-monitoring.sh` | Install the database self-monitoring (schema, samplers, jobs). |

## Configuration

| File | Purpose |
|---|---|
| `.env` | All settings/secrets (copy from `.env.example`; git-ignored). |
| `docker-compose.yml` | Service definitions, compose profiles and pinned image versions. |
| `keycloak/realms/perfana-realm.json` | Imported `perfana-prod` realm (clients, roles, admin user). |
| `grafana/provisioning/datasources/datasources.yaml` | Grafana data source (Perfana TimescaleDB). |
| `perfana/provisioning/` | Perfana benchmark / dashboard provisioning applied by the API. |
| `database/init/` | PostgreSQL init (creates the Keycloak and Grafana databases). |
| `pgbouncer/pgbouncer.ini` | Connection pooler settings (optional, load generators only). |
| `monitoring/pg-monitoring.sql` | Database self-monitoring: schema, samplers, background jobs. |
| `monitoring/redis-sampler.py` | Samples Valkey and the BullMQ queue depths into the same hypertable. |
| `monitoring/docker-sampler.py` | Samples per-container CPU, memory and I/O into the same hypertable. |

## Connection pooling for load generators (optional)

PgBouncer is included but off by default. The Perfana services connect to PostgreSQL directly
and always will — the pooler exists only for **load generator** traffic, so a fleet of
distributed JMeter generators does not exhaust `max_connections`.

```bash
./scripts/mint-pgbouncer-userlist.sh          # once, and after any password change
podman compose --profile pgbouncer up -d pgbouncer
```

It listens on `6432` and needs its own firewall rule. Full steps in [INSTALL.md](INSTALL.md)
step 9.

## Database monitoring

Two TimescaleDB background jobs sample the `pg_stat_*` catalogs into a hypertable in the
`monitoring` schema — no exporter, no Prometheus, no extra container:

```bash
./scripts/setup-db-monitoring.sh
```

Connections, transaction and tuple rates, cache hit ratio, WAL generation and `pg_wal` size,
checkpoints and buffer writes, continuous-aggregate job failures, hypertable growth and dead
tuples. `valkey-monitor` adds Valkey and the BullMQ queues; `docker-monitor` adds per-container
CPU, memory and I/O. Seven days of history, then dropped by a retention policy.

The dashboards that read this data need the `grafana` profile. The sampling itself runs either
way, so the history is already there when you enable it.

## Health checks

- Perfana UI — `http://localhost:4001`
- Perfana API — `http://localhost:3001/api/health`
- Keycloak — `http://localhost:8080`
- Grafana — `http://localhost:3100` (only with the `grafana` profile)

See [INSTALL.md](INSTALL.md) for prerequisites, Podman and Compose installation, the Podman API
socket, SELinux, systemd auto-start, backups, upgrades, air-gapped installs and troubleshooting.
