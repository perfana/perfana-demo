# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this repository is

A **production deployment** of Perfana for **Windows Server 2025**, running in **WSL2** with
**Docker Engine CE** (no Docker Desktop). It is configuration only — there is no application
source code here; the Perfana services run from pinned `perfana/*` Docker images.

The authoritative install instructions live in **[INSTALL.md](INSTALL.md)**.

## Deployed components

Perfana platform: `postgres` (TimescaleDB), `keycloak`, `perfana-migration` (one-shot),
`perfana-api`, `perfana-web`, `perfana-worker`, `perfana-grafana-sync`, `perfana-report`,
`valkey` (Redis-compatible). Plus a `grafana` instance that provisions Perfana's own TimescaleDB
data source; other data sources are added from the Grafana UI as needed.

## Key files

- `docker-compose.yml` — the 10-service stack; browser-facing URLs derive from `PERFANA_HOST` /
  `PERFANA_SCHEME`; persistent state is in named volumes (Docker `data-root` lives on the
  dedicated share — see INSTALL.md).
- `.env.example` — every setting/secret; copied to git-ignored `.env`. Required vars use
  `${VAR:?}` in compose, so the stack refuses to start if they're unset.
- `start.sh` / `stop.sh` / `update.sh` — lifecycle (start in dependency order, stop, upgrade).
- `bootstrap.sh` — one-time first-run integration (aligns Keycloak to `PERFANA_HOST`, creates the
  org + admin, applies provisioning, registers Grafana, mints an API key). Server-local over
  `localhost`.
- `keycloak/realms/perfana-realm.json` — imported `perfana-prod` realm (clients, roles, the
  `admin@perfana.io` bootstrap user).
- `grafana/provisioning/datasources/datasources.yaml` — provisions Perfana's TimescaleDB
  (stable UID `postgres-timescaledb`, referenced by the dashboards — don't rename). Other
  data sources are added from the Grafana UI.
- `grafana/dashboards/` — the `template-timescaledb-*` dashboards.
- `perfana/provisioning/` — the `jmeter` profile's benchmark/dashboard catalog applied by
  `perfana-api` on boot (mounted at `/data/provisioning`).
- `database/init/` — PostgreSQL init (creates the Keycloak and Grafana databases, pre-seeds a
  migration record). Grafana uses Postgres for its own backend state (see `grafana/grafana.ini`).

## Working conventions

- Keep `docker-compose.yml` parseable: `docker compose config -q` (with required env set) must
  pass.
- The realm JSON must remain valid JSON after edits (`python3 -m json.tool`).
- `ENCRYPTION_KEY` must never change after first run — note this in any change that touches it.
- Keep the deployment lean: it is the Perfana platform plus Grafana, nothing more.
- Bash scripts: keep `bash -n` clean and prefer guarded best-effort steps in `bootstrap.sh`
  (warn, don't abort) so partial runs are recoverable and re-runnable.
