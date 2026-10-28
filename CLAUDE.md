# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this repository is

A **production deployment** of Perfana for **RHEL 9**, running on **Podman** with
`podman-compose`. Docker Compose v2 is deliberately not used.
It is configuration only — there is no application source code here; the Perfana services run
from pinned `perfana/*` images.

Grafana is **optional**, behind the `grafana` compose profile. The core stack must stay usable
without it: anything that only works with Grafana belongs in that profile.

The authoritative install instructions live in **[INSTALL.md](INSTALL.md)**.

## Deployed components

Core: `postgres` (TimescaleDB), `valkey` (Redis-compatible), `keycloak`, `perfana-migration`
(one-shot), `perfana-api`, `perfana-web`, `perfana-worker`, `perfana-report`,
`docker-socket-proxy`, and the `valkey-monitor` / `docker-monitor` samplers.

Profiles: `grafana` (`grafana` + `perfana-grafana-sync`), `pgbouncer` (`pgbouncer`). Activated
through `COMPOSE_PROFILES` in `.env`.

## Key files

- `docker-compose.yml` — the stack; browser-facing URLs derive from `PERFANA_HOST` /
  `PERFANA_SCHEME`; persistent state is in named volumes. Every bind mount carries a `:z`
  SELinux label, and `docker-socket-proxy` mounts `${PODMAN_SOCKET}`.
- `.env.example` — every setting/secret; copied to git-ignored `.env`. Required vars use
  `${VAR:?}` in compose, so the stack refuses to start if they're unset.
- `start.sh` / `stop.sh` / `update.sh` — lifecycle (start in dependency order, stop, upgrade).
- `bootstrap.sh` — one-time first-run integration (aligns Keycloak to `PERFANA_HOST`, creates the
  org + admin, applies provisioning, registers Grafana, mints an API key). Server-local over
  `localhost`. Its Grafana steps are guarded by `grafana_enabled`.
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

- Keep `docker-compose.yml` parseable: `podman-compose config` (with required env set) must
  pass.
- Never rely on `depends_on: condition: service_healthy` for correctness — `podman-compose`
  does not implement it. `start.sh` / `update.sh` poll `podman inspect` for health instead.
- Scripts call the runtime through the `CONTAINER_CLI` / `COMPOSE` arrays defined at the top of
  each one, never `docker`/`podman` literally, so the same scripts run under either runtime.
- A new service that needs Grafana goes in the `grafana` profile, and any script step touching
  it goes behind `grafana_enabled`.
- The realm JSON must remain valid JSON after edits (`python3 -m json.tool`).
- `ENCRYPTION_KEY` must never change after first run — note this in any change that touches it.
- Keep the deployment lean: it is the core Perfana platform, plus the two optional profiles,
  nothing more.
- Bash scripts: keep `bash -n` clean and prefer guarded best-effort steps in `bootstrap.sh`
  (warn, don't abort) so partial runs are recoverable and re-runnable.
