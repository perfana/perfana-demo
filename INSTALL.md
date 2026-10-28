# Installing Perfana on RHEL 9 with Podman

This deploys the **core Perfana stack** — PostgreSQL/TimescaleDB, Valkey, Keycloak and the five
Perfana services — on a single Red Hat Enterprise Linux 9 host using Podman and Compose.

Grafana is **optional** here. The core stack runs load tests, stores results, evaluates
requirements and runs ADAPT regression analysis without it. Turn it on when you want metric
panels, dashboard snapshots in reports, and dashboard sync.

The deployment is accessed on the server itself over `http://localhost`. Exposing it to the
network and adding TLS are out of scope; see [12. Access Perfana](#12-access-perfana).

## Table of contents

1. [What gets deployed](#1-what-gets-deployed)
2. [Sizing & prerequisites](#2-sizing--prerequisites)
3. [Install Podman and a Compose provider](#3-install-podman-and-a-compose-provider)
4. [Enable the Podman API socket](#4-enable-the-podman-api-socket)
5. [Prepare the deployment directory](#5-prepare-the-deployment-directory)
6. [SELinux](#6-selinux)
7. [Deploy Perfana](#7-deploy-perfana)
8. [Enable Grafana (optional)](#8-enable-grafana-optional)
9. [Expose PostgreSQL and PgBouncer (optional)](#9-expose-postgresql-and-pgbouncer-optional)
10. [Database monitoring (recommended)](#10-database-monitoring-recommended)
11. [Install perfana-cli on the load generators](#11-install-perfana-cli-on-the-load-generators)
12. [Access Perfana](#12-access-perfana)
13. [Start automatically on boot](#13-start-automatically-on-boot)
14. [Backups](#14-backups)
15. [Upgrades](#15-upgrades)
16. [Troubleshooting](#16-troubleshooting)
17. [Load images offline (air-gapped)](#17-load-images-offline-air-gapped)

---

## 1. What gets deployed

**Core** — always started:

| Service | Image | Purpose | Browser port |
|---|---|---|---|
| `postgres` | timescale/timescaledb-ha:pg15 | Perfana + Keycloak databases | 5432 (LAN, opt-in) |
| `valkey` | valkey/valkey:8-alpine | Job queue (Redis-compatible) | 6379 (loopback) |
| `keycloak` | quay.io/keycloak/keycloak:24.0 | Authentication / SSO | 8080 |
| `perfana-migration` | perfana/perfana-migration | One-shot DB migrations | — |
| `perfana-api` | perfana/perfana-api | REST API (NestJS) | 3001 |
| `perfana-web` | perfana/perfana-web | UI (Next.js) | 4001 (`PERFANA_WEB_PORT`) |
| `perfana-worker` | perfana/perfana-worker | Analysis pipeline | — |
| `perfana-report` | perfana/perfana-report | PDF reports | — |
| `docker-socket-proxy` | tecnativa/docker-socket-proxy | Read-only API gateway for the admin log viewer | — |
| `valkey-monitor`, `docker-monitor` | timescale/timescaledb-ha:pg15 | Samplers for the health dashboards | — |

**Optional** — activated through `COMPOSE_PROFILES` in `.env`:

| Profile | Services | What it adds |
|---|---|---|
| `grafana` | `grafana`, `perfana-grafana-sync` | Metric panels, dashboard snapshots in reports, dashboard sync. Port 3100 (`GRAFANA_PORT`). |
| `pgbouncer` | `pgbouncer` | Connection pooler for load generators opening many short-lived connections. Port 6432. |

Valkey is bound to `127.0.0.1` and is not reachable from the network.

### Running without Grafana

Perfana's own data — transactions, requests, errors, traces — comes from the load generator
straight into TimescaleDB, so these keep working with the `grafana` profile off:

- running tests and storing results
- transaction and request statistics, trends, run comparison
- requirements and benchmark checks on load-test metrics
- ADAPT regression analysis on those metrics
- error analysis and the HTML/PDF report for everything above

What you lose: any panel sourced from a Grafana data source (application, infrastructure,
Dynatrace), the dashboard snapshots embedded in reports, and `perfana-grafana-sync`. You can add
the profile later without reinstalling — see [step 8](#8-enable-grafana-optional).

---

## 2. Sizing & prerequisites

**Host:**

- RHEL 9.4 or later (or a compatible rebuild), fully patched and registered to a repository
  that carries `podman` and `podman-compose`/`docker-compose`.
- `sudo` rights.
- Outbound access to `quay.io`, `docker.io` and (if you enable Grafana) the Grafana plugin CDN —
  or an internal mirror, or the offline bundle from [step 17](#17-load-images-offline-air-gapped).

**Recommended resources:**

| | Minimum | Recommended |
|---|---|---|
| vCPU | 4 | 8 |
| RAM | 12 GB | 16–24 GB |
| Disk (`/srv/perfana`) | 80 GB | 200 GB+ (grows with test history) |

Add ~2 GB RAM if you enable the `grafana` profile.

**Ports used on the server:** `4001` (UI, `PERFANA_WEB_PORT`), `3001` (API), `8080` (Keycloak),
and with the optional profiles `3100` (Grafana, `GRAFANA_PORT`) and `6432` (PgBouncer). All are
above 1024, so a rootless install can publish them.

---

## 3. Install Podman and a Compose provider

```bash
sudo dnf -y install podman
```

Optionally add `podman-docker`, which provides a `docker` shim. Nothing here needs it — the
scripts call `podman` directly — but it keeps third-party tooling working.

### Compose provider

Podman does not implement Compose itself. `podman compose` is a dispatcher: it looks up an
external provider on `PATH` and runs it. Use **Docker Compose v2** (Apache-2.0; the subscription
terms that cover Docker Desktop do not apply to the standalone plugin):

```bash
sudo dnf -y install docker-compose-plugin 2>/dev/null || {
  ARCH=$(uname -m)
  sudo curl -fsSL -o /usr/local/bin/docker-compose \
    "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${ARCH}"
  sudo chmod +x /usr/local/bin/docker-compose
}
```

Point Podman at it with a drop-in, so a package update cannot overwrite the setting and the
provider does not depend on the caller's `PATH` (which matters once systemd starts the stack):

```bash
sudo mkdir -p /etc/containers/containers.conf.d
sudo tee /etc/containers/containers.conf.d/50-compose.conf >/dev/null <<'EOF'
[engine]
compose_providers = ["/usr/local/bin/docker-compose"]
compose_warning_logs = false
EOF
```

Rootless: put the same file in `~/.config/containers/containers.conf.d/`.

```bash
podman --version
podman compose version      # must report a Compose v2 version
```

Compose v2 speaks the Docker Engine API, so it needs the Podman socket from
[step 4](#4-enable-the-podman-api-socket) — `podman compose` sets `DOCKER_HOST` to that socket
before launching the provider.

> `podman-compose` (the Python implementation) also works and needs no socket for Compose
> itself. If you prefer it, install it and run the scripts with
> `COMPOSE=podman-compose ./start.sh`. The one thing it does not do is honour
> `depends_on: condition: service_healthy` — which, see below, this deployment does not rely on
> either way.

### Startup ordering

`start.sh` and `update.sh` wait for PostgreSQL to report healthy — by polling `podman inspect` —
before running database migrations, instead of leaning on
`depends_on: condition: service_healthy`. Compose v2 honours that condition, so this is
belt-and-braces there; it is what makes the same scripts correct under `podman-compose` too.

Both scripts also name every core service explicitly rather than running a bare `up -d`, so the
optional `grafana` / `pgbouncer` profiles stay off regardless of how well the provider
implements `profiles:`.

The practical consequence either way: bring the stack up with `./start.sh`, not with a bare
`podman compose up -d`.

---

## 4. Enable the Podman API socket

The admin log viewer in the Perfana UI streams container logs. `perfana-api` never touches the
socket directly: it talks to `docker-socket-proxy` over TCP, and that proxy filters the API down
to read-only container operations (`CONTAINERS=1`, `POST=0`). Only the proxy mounts the socket.

**Rootful (recommended for a shared server):**

```bash
sudo systemctl enable --now podman.socket
sudo systemctl is-active podman.socket        # active
ls -l /run/podman/podman.sock
```

Leave `PODMAN_SOCKET=/run/podman/podman.sock` in `.env` (the default).

**Rootless:**

```bash
systemctl --user enable --now podman.socket
loginctl enable-linger "$USER"                # keep user services alive after logout
echo "/run/user/$(id -u)/podman/podman.sock"
```

Set that path as `PODMAN_SOCKET` in `.env`.

> Skipping this step does not stop the stack from starting — only the admin log viewer fails.

---

## 5. Prepare the deployment directory

```bash
sudo mkdir -p /srv/perfana
sudo chown "$USER:$USER" /srv/perfana
cd /srv/perfana
```

Container storage (images and named volumes) lives under `/var/lib/containers` for rootful
Podman and `~/.local/share/containers` for rootless. If that filesystem is small, point Podman
at a larger one **before** pulling images:

```bash
# rootful: /etc/containers/storage.conf
sudo sed -i 's|^graphroot = .*|graphroot = "/srv/perfana/containers/storage"|' \
  /etc/containers/storage.conf
sudo mkdir -p /srv/perfana/containers/storage
sudo systemctl restart podman.socket
podman info --format '{{.Store.GraphRoot}}'   # confirm
```

Put the database on a local filesystem (xfs or ext4). Never put PostgreSQL data on NFS or SMB.

---

## 6. SELinux

Leave SELinux in enforcing mode. Podman does not relabel bind mounts automatically, so every
bind mount in `docker-compose.yml` carries a `:z` suffix — the shared label that lets containers
read these project directories:

```
./database/init        ./keycloak/realms      ./monitoring
./pgbouncer/*          ./perfana/provisioning ./grafana/*
```

You do not have to do anything for those; the first `./start.sh` relabels them. Two things to
know:

- `:z` relabels the directory **on the host**. If `/srv/perfana` is shared with another tool
  that cares about its SELinux context, that context changes.
- Named volumes (`perfana`, `valkey-storage`, `grafana-storage`, `libredb-data`) are managed by
  Podman and labelled correctly on their own.

Check for denials if a container cannot read its config:

```bash
sudo ausearch -m avc -ts recent
```

---

## 7. Deploy Perfana

### 7.1 Get the deployment files onto the server

```bash
cd /srv/perfana
git clone --branch poc-rhel-podman <repository-url> app
cd app
```

Air-gapped: copy the directory across by other means; only the files in this repository are
needed.

### 7.2 Configure `.env`

```bash
cp .env.example .env
chmod 600 .env
```

Generate strong secrets:

```bash
openssl rand -base64 24   # POSTGRES_PASSWORD, admin passwords
openssl rand -hex 32      # ENCRYPTION_KEY and the client secrets
```

Edit `.env` and set **every** value. The important ones:

| Variable | Set to |
|---|---|
| `PERFANA_HOST` | `localhost` for this server-local deployment (the default). |
| `PERFANA_SCHEME` | `http` (the default; no TLS in this deployment). |
| `PODMAN_SOCKET` | Socket path from [step 4](#4-enable-the-podman-api-socket). |
| `COMPOSE_PROFILES` | Empty for core only. `grafana` and/or `pgbouncer` to add those. |
| `POSTGRES_PASSWORD` | Strong random value. |
| `KEYCLOAK_ADMIN_PASSWORD` | Strong random value (Keycloak console admin). |
| `ENCRYPTION_KEY` | 64-hex string. **Never change after first run.** |
| `KEYCLOAK_CLIENT_SECRET` / `KEYCLOAK_ADMIN_CLIENT_SECRET` | Random secrets; `bootstrap.sh` writes these into Keycloak. |
| `GRAFANA_ADMIN_PASSWORD` / `GRAFANA_OAUTH_CLIENT_SECRET` | Only needed with the `grafana` profile, but the compose file requires them to be non-empty — set a random value either way. |
| `PERFANA_ADMIN_USER` / `PERFANA_ADMIN_PASSWORD` | The initial Perfana admin login (`bootstrap.sh` sets the password). |

### 7.3 Start the stack

> **Air-gapped?** Load the images first — see
> [17. Load images offline](#17-load-images-offline-air-gapped) — then continue here.

```bash
./start.sh
```

This starts PostgreSQL and Valkey, runs migrations, waits for Keycloak to become healthy (realm
imported), then starts the Perfana services — and Grafana only if its profile is active.

```bash
podman compose ps
podman compose logs -f perfana-api
```

### 7.4 Run first-run bootstrap (once)

```bash
./bootstrap.sh
```

Idempotent, safe to re-run. It aligns Keycloak with `.env` and `PERFANA_HOST`, sets the admin
password, creates the Perfana organization, applies the benchmark/dashboard provisioning under
that organization, registers Grafana (skipped when the profile is off), and prints a **Perfana
API key** for load generators — stored nowhere else, so copy it out.

### 7.5 Verify

```bash
curl -fsS http://localhost:3001/api/health && echo OK    # API
podman compose ps                                        # all services Up/healthy
```

Then browse to `http://localhost:4001` and log in as `PERFANA_ADMIN_USER`.

---

## 8. Enable Grafana (optional)

Grafana can be added at any time; nothing needs reinstalling.

1. Set the profile and secrets in `.env`:

   ```bash
   COMPOSE_PROFILES=grafana
   GRAFANA_ADMIN_PASSWORD=<strong value>
   GRAFANA_OAUTH_CLIENT_SECRET=<random hex>
   ```

2. Start the profile's services and re-run bootstrap so Keycloak gets Grafana's redirect URIs
   and Perfana gets a Grafana service-account token:

   ```bash
   ./start.sh
   ./bootstrap.sh
   ```

3. Verify:

   ```bash
   curl -fsS http://localhost:3100/api/health && echo OK
   ```

Only Perfana's own TimescaleDB data source is provisioned. Add Prometheus, Loki, Dynatrace and
the rest from the Grafana UI; they must be reachable from inside the container network.

To remove Grafana again, clear `COMPOSE_PROFILES` and run
`podman compose --profile grafana down grafana perfana-grafana-sync`. The `grafana-storage`
volume survives, so re-enabling keeps your dashboards.

---

## 9. Expose PostgreSQL and PgBouncer (optional)

`docker-compose.yml` binds PostgreSQL on all interfaces so remote load generators and BI tools
can reach it. Open the host firewall only if you actually need that:

```bash
sudo firewall-cmd --permanent --add-port=5432/tcp
sudo firewall-cmd --reload
```

For load generators that open many short-lived connections, enable the pooler instead of
pointing them at PostgreSQL directly:

```bash
./scripts/mint-pgbouncer-userlist.sh      # writes pgbouncer/userlist.txt from .env
# add pgbouncer to COMPOSE_PROFILES in .env, then:
podman compose --profile pgbouncer up -d pgbouncer
sudo firewall-cmd --permanent --add-port=6432/tcp && sudo firewall-cmd --reload
```

---

## 10. Database monitoring (recommended)

Creates the `monitoring` schema that the PostgreSQL, Valkey and container-resource dashboards
read, and enables `pg_stat_statements`:

```bash
./scripts/setup-db-monitoring.sh
```

The samplers (`valkey-monitor`, `docker-monitor`) are part of the core stack and start with it.
`docker-monitor` reads container stats through `docker-socket-proxy`, so it needs the Podman
socket from [step 4](#4-enable-the-podman-api-socket).

---

## 11. Install perfana-cli on the load generators

`perfana-cli` orchestrates a test run: it opens the run in Perfana, starts the load generator,
sends keep-alives while it runs, and closes the run so the analysis pipeline picks it up. It
does **not** belong on the Perfana server — install it wherever the load generator runs
(JMeter, k6, Gatling).

Source and releases: <https://github.com/perfana/perfana-cli>

### Install from the GitHub release

Binaries are published per platform as `perfana-cli_<version>_<os>_<arch>.tar.gz`. Pick a
version rather than `latest` so a rebuilt generator gets the same binary:

```bash
PERFANA_CLI_VERSION=0.7.4
ARCH=$([ "$(uname -m)" = "aarch64" ] && echo arm64 || echo amd64)

curl -fsSL -o /tmp/perfana-cli.tar.gz \
  "https://github.com/perfana/perfana-cli/releases/download/v${PERFANA_CLI_VERSION}/perfana-cli_${PERFANA_CLI_VERSION}_linux_${ARCH}.tar.gz"

sudo tar -xzf /tmp/perfana-cli.tar.gz -C /usr/local/bin perfana-cli
rm /tmp/perfana-cli.tar.gz

perfana-cli --version
```

Verify the download against the release's `checksums.txt` if your policy requires it:

```bash
curl -fsSL -O "https://github.com/perfana/perfana-cli/releases/download/v${PERFANA_CLI_VERSION}/checksums.txt"
sha256sum -c checksums.txt --ignore-missing
```

Air-gapped: fetch the tarball and `checksums.txt` on a connected machine, copy both across, and
run the same `tar -xzf`. The binary is static — no runtime dependencies beyond glibc.

### Configure it

`perfana-cli` reads a YAML config, by default `$HOME/.perfana-cli/perfana.yaml`, overridable
with `--config`. The two things it needs from this deployment:

| Setting | Value |
|---|---|
| `perfana.apiUrl` | `http://<perfana-host>:3001` — the API, reachable from the generator. |
| `perfana.apiKey` | The key `bootstrap.sh` printed in [step 7.4](#74-run-first-run-bootstrap-once). |

A minimal config:

```yaml
perfana:
  apiKey: "<the key bootstrap.sh printed>"
  apiUrl: "http://perfana.internal:3001"
  appUrl: "http://perfana.internal:4001"
test:
  systemUnderTest: "MyApp"
  environment: "acc"
  workload: "loadTest"
  version: "1.0.0"
```

The API key is shown once, at bootstrap. Lost it? Create a new one in the Perfana UI under
**Settings → API keys**.

Reaching port 3001 from another host needs a firewall rule, the same as
[step 9](#9-expose-postgresql-and-pgbouncer-optional):

```bash
sudo firewall-cmd --permanent --add-port=3001/tcp
sudo firewall-cmd --reload
```

Run a test with:

```bash
perfana-cli run start --config ./perfana.yaml --version 1.0.0
```

### Example: a k6 run with the customised image

The k6 image built from perfana-demo's `k6/Dockerfile` carries the pieces a run needs: the
`perfana-timescaledb` output, the Kafka and IBM MQ extensions, and `perfana-cli` itself. So the
generator does not need a local k6 or CLI install — everything happens inside the container.

Lay out a directory on the generator:

```
/srv/loadtest/
├── perfana.yaml
├── run-k6.sh
└── src/test/k6/my-test.js
```

`perfana.yaml` — the CLI config *and* the run definition. `events.onStartTest` is what actually
launches k6; `onKeepAlive` tells Perfana the run is still alive; `onAbort` kills it on Ctrl-C or
a failed keep-alive:

```yaml
perfana:
  apiKey: "<the key bootstrap.sh printed>"
  apiUrl: "http://perfana.internal:3001"
  appUrl: "http://perfana.internal:4001"

test:
  systemUnderTest: "MyApp"
  environment: "acc"
  workload: "loadTest"
  version: "${SUT_VERSION}"
  # Trim ramp-up and ramp-down out of the analysis window.
  analysisStartOffset: "PT1M"
  analysisEndOffset: "PT30S"
  constantLoadTime: "PT5M"
  tags:
    - "k6"

scheduler:
  enabled: true
  failOnError: true
  keepAliveIntervalSeconds: 30

events:
  - name: "k6-load"
    type: command
    continueOnKeepAliveParticipant: true
    commands:
      onStartTest: "/tests/run-k6.sh __testRunId__"
      onKeepAlive: "pgrep -f 'k6 run' >/dev/null || exit 1"
      onAbort: "pkill -f 'k6 run'"
```

`run-k6.sh` — `__testRunId__` is substituted by the CLI and has to reach both the output and the
script, so the rows can be tied to the run:

```bash
#!/bin/sh
TEST_RUN_ID="$1"

: "${TIMESCALE_URL:=postgres://perfana:CHANGEME@perfana.internal:5432/perfana?sslmode=prefer}"

# Fork-only, and off by default: fills requests_error with request/response
# headers and bodies, and keeps the real URL of a request that sets a name tag.
export K6_HTTP_ERROR_DATA=true
export K6_HTTP_REQUEST_URL=true

k6 run /tests/src/test/k6/my-test.js \
  -e TEST_RUN_ID="$TEST_RUN_ID" \
  --tag testRunId="$TEST_RUN_ID" \
  --out "perfana-timescaledb=url=${TIMESCALE_URL},runId=${TEST_RUN_ID},systemUnderTest=MyApp,testEnvironment=acc,scenarioName=MyScenario,location=generator-1,nodeName=$(hostname)"
```

Start the run — the CLI is the container's entrypoint command, and the directory is mounted at
`/tests`:

```bash
podman run --rm \
  -v /srv/loadtest:/tests:ro,z \
  -e SUT_VERSION=1.0.0 \
  <registry>/perfana-k6:<tag> \
    perfana-cli run start --config /tests/perfana.yaml --version 1.0.0
```

The CLI opens the run in Perfana, runs `run-k6.sh`, keeps the run alive, closes it, waits for
the analysis, and prints the verdict plus a link to the test run. It exits non-zero when an SLO
or the ADAPT comparison fails, which is what makes it usable as a pipeline gate.

Two things specific to this image:

- It is **linux/amd64 only** (the IBM MQ client, see [step 1](#1-what-gets-deployed)). Add
  `--platform linux/amd64` on an arm64 generator.
- The `:z` on the mount is the SELinux relabel, the same reason as everywhere else here.

Writing straight to port 5432 is fine for one generator. For a fleet opening many short-lived
connections, point `TIMESCALE_URL` at PgBouncer on 6432 instead — see
[step 9](#9-expose-postgresql-and-pgbouncer-optional).

---

## 12. Access Perfana

Accessed over plain HTTP at `http://localhost`, from the server itself (console or SSH port
forward):

| Service | URL |
|---|---|
| Perfana UI | `http://localhost:4001` |
| Perfana API | `http://localhost:3001/api/health` |
| Keycloak | `http://localhost:8080` |
| Grafana (if enabled) | `http://localhost:3100` |

From a workstation, forward the ports over SSH rather than opening the firewall:

```bash
ssh -L 4001:localhost:4001 -L 3001:localhost:3001 -L 8080:localhost:8080 user@server
```

> Publishing Perfana on the network with TLS is out of scope. If you need it, terminate TLS on a
> reverse proxy in front of the published ports, set `PERFANA_HOST`/`PERFANA_SCHEME` to the
> public name and scheme, then run `./stop.sh && ./start.sh && ./bootstrap.sh` so the Keycloak
> redirect URIs and Grafana root URL follow.

---

## 13. Start automatically on boot

Two pieces: the compose `restart: unless-stopped` policy brings containers back once Podman is
running, and a systemd unit brings the stack up after a reboot.

**Rootful**, `/etc/systemd/system/perfana.service`:

```ini
[Unit]
Description=Perfana stack
Requires=podman.socket
After=network-online.target podman.socket
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/srv/perfana/app
ExecStart=/srv/perfana/app/start.sh
ExecStop=/srv/perfana/app/stop.sh
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now perfana.service
```

**Rootless:** put the same unit in `~/.config/systemd/user/perfana.service`, drop the `[Install]`
target to `default.target`, enable it with `systemctl --user enable --now perfana.service`, and
make sure `loginctl enable-linger "$USER"` is set — otherwise the stack stops when you log out.

> Podman's `podman generate systemd` and Quadlet produce one unit per container and will fight
> the compose file over start order. Driving `start.sh` from a single oneshot unit keeps the
> dependency handling in one place.

---

## 14. Backups

The database is the only thing you cannot recreate.

```bash
# One-off
podman exec perfana-postgres pg_dump -U perfana -Fc perfana > /mnt/backup/perfana-$(date +%F).dump

# Restore (into a fresh, empty database)
cat /mnt/backup/perfana-YYYY-MM-DD.dump | \
  podman exec -i perfana-postgres pg_restore -U perfana -d perfana --clean --if-exists
```

Schedule it from cron or a systemd timer, writing to a mounted network share. Also back up
`.env` to a secrets store — it holds the `ENCRYPTION_KEY`, and without it every stored secret
(Grafana tokens, data source passwords) is unrecoverable.

---

## 15. Upgrades

1. Back up the database (above).
2. Edit `docker-compose.yml` and bump the pinned `perfana/*` image tags. Keep
   `perfana-migration` on the matching version.
3. Apply:

   ```bash
   ./update.sh
   ```

   Pulls images, re-runs migrations, recreates changed services. The `ENCRYPTION_KEY` and all
   named volumes are preserved.
4. Verify health as in [step 7.5](#75-verify).

---

## 16. Troubleshooting

| Symptom | Check |
|---|---|
| `start.sh`: "POSTGRES_PASSWORD must be set" | `.env` missing or value empty. Every `${VAR:?}` variable is required. |
| Container cannot read a config file; `Permission denied` | SELinux. Confirm the mount carries `:z` in `docker-compose.yml` and check `sudo ausearch -m avc -ts recent`. |
| Admin log viewer empty / API logs "fetch failed" to docker-socket-proxy | Podman socket not enabled or wrong `PODMAN_SOCKET`. See [step 4](#4-enable-the-podman-api-socket). |
| Migrations fail against a database that is still starting | You brought the stack up with a bare `podman compose up -d` instead of `./start.sh`. Only the scripts wait for PostgreSQL to report healthy ([step 3](#3-install-podman-and-a-compose-provider)). |
| `podman compose` runs the wrong provider | `podman compose version` must report Compose v2. If it reports `podman-compose`, fix `compose_providers` in `/etc/containers/containers.conf.d/50-compose.conf` ([step 3](#3-install-podman-and-a-compose-provider)). |
| Keycloak never becomes healthy | `podman compose logs keycloak`. Usually the DB isn't ready, or the realm failed to import. |
| Login redirects fail / "invalid redirect URI" | Browse via `http://localhost`, not the machine name. If you changed `PERFANA_HOST`, run `./stop.sh && ./start.sh && ./bootstrap.sh`. |
| API rejects tokens ("issuer not accepted") | Reach Keycloak on `http://localhost:8080`. The API accepts `keycloak:8080`, `localhost:8080` and `<PERFANA_HOST>:8080`. |
| Grafana panels empty / "datasource not found" | Only `postgres-timescaledb` is provisioned. Add the others from the Grafana UI. |
| Perfana shows no metric panels at all | The `grafana` profile is off. That is the documented core-only behaviour — see [step 8](#8-enable-grafana-optional). |
| Rootless: containers die at logout | `loginctl enable-linger "$USER"`. |
| PDF report generation fails / OOM | `perfana-report` runs Chromium. Give the host more free RAM or add swap. |
| Disk filling up | `podman system df`; prune unused images with `podman image prune -a`. Test history growth is in the `perfana` volume. |

Useful commands:

```bash
podman compose ps                     # status of all services
podman compose logs -f <service>      # follow a service's logs
podman compose restart <service>      # restart one service
podman stats                          # live CPU/RAM per container
./stop.sh                             # stop (keep data)
./stop.sh --volumes                   # stop and DELETE all data (destructive)
```

---

## 17. Load images offline (air-gapped)

If the server has no registry access, load pre-saved image archives before `./start.sh`:

```bash
for f in /srv/perfana/images/*.tar; do
  podman load -i "$f"
done

podman images      # confirm every image in docker-compose.yml is present
```

To produce the archives on a connected machine:

```bash
for img in $(grep -oE '^\s+image: \S+' docker-compose.yml | awk '{print $2}' | sort -u); do
  podman pull "$img"
  podman save -o "$(echo "$img" | tr '/:' '__').tar" "$img"
done
```

Skip the `grafana/grafana` image if you are not enabling that profile. Then start as in
[7.3](#73-start-the-stack) — the images resolve locally and nothing is pulled.
