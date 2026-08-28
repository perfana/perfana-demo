# Perfana on Windows Server 2025 (WSL2 + Docker Engine CE)

A **production** Perfana deployment for **Windows Server 2025**, running in **WSL2** with
**Docker Engine CE** (no Docker Desktop). It deploys the Perfana platform and a Grafana instance
that provisions Perfana's own TimescaleDB data source. Add other Grafana data sources from the UI
after install.

> **Full instructions: [INSTALL.md](INSTALL.md).** This README is the short version.

## Components

Perfana platform (`postgres`, `keycloak`, `perfana-migration`, `perfana-api`, `perfana-web`,
`perfana-worker`, `perfana-grafana-sync`, `perfana-report`, `valkey`) plus a `grafana`
instance provisioning Perfana's TimescaleDB data source.

## Quick start

Assuming WSL2, Docker Engine CE, and the dedicated share are already set up per
[INSTALL.md](INSTALL.md):

```bash
cp .env.example .env       # then edit: set the secrets (host defaults to localhost)
./start.sh                 # start DB, migrate, start Keycloak + Perfana + Grafana
./bootstrap.sh             # first run only: org, admin, Grafana registration, API key
```

Browse to `http://localhost:4001` (`PERFANA_WEB_PORT`) on the server.

## Scripts

| Script | Purpose |
|---|---|
| `start.sh` | Start the stack in dependency order (DB → migrate → Keycloak → services). |
| `stop.sh` | Stop containers (`--volumes` to also delete data — destructive). |
| `update.sh` | Pull pinned images, re-run migrations, recreate services. |
| `bootstrap.sh` | One-time first-run integration setup. |
| `scripts/mint-pgbouncer-userlist.sh` | Write `pgbouncer/userlist.txt` from `POSTGRES_PASSWORD`. |

## Configuration

| File | Purpose |
|---|---|
| `.env` | All settings/secrets (copy from `.env.example`; git-ignored). |
| `docker-compose.yml` | Service definitions and pinned image versions. |
| `keycloak/realms/perfana-realm.json` | Imported `perfana-prod` realm (clients, roles, admin user). |
| `grafana/provisioning/datasources/datasources.yaml` | Grafana data source (Perfana TimescaleDB). |
| `perfana/provisioning/` | Perfana benchmark / dashboard provisioning applied by the API. |
| `database/init/` | PostgreSQL init (creates the Keycloak and Grafana databases). |
| `pgbouncer/pgbouncer.ini` | Connection pooler settings (optional, load generators only). |

## Connection pooling for load generators (optional)

PgBouncer is included but **off by default**. The Perfana services connect to
PostgreSQL directly and always will — the pooler exists only for **load generator**
traffic, so a fleet of distributed JMeter generators does not exhaust
`max_connections`.

```bash
./scripts/mint-pgbouncer-userlist.sh          # once, and after any password change
docker compose --profile pgbouncer up -d pgbouncer
```

It listens on `6432` and needs its own firewall rule. Full steps, including pointing
the JMeter backend listener at it: [INSTALL.md](INSTALL.md) steps 9.7 and 9.8.

## Health checks

- Perfana UI — `http://localhost:4001`
- Perfana API — `http://localhost:3001/api/health`
- Keycloak — `http://localhost:8080`
- Grafana — `http://localhost:3100`

See [INSTALL.md](INSTALL.md) for prerequisites, WSL2 resource allocation, the dedicated share,
Docker CE installation, localhost access, auto-start, backups, upgrades, and troubleshooting.
