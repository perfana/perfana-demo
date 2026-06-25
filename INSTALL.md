# Installing Perfana on Windows Server 2025 (WSL2 + Docker Engine CE)

This guide installs a **production** Perfana deployment on **Windows Server 2025**, running
inside **WSL2** with **Docker Engine (Community Edition)**. **Docker Desktop is not used** and
is not required (it is also not licensed for this scenario).

This is not the demo environment. It deploys only the components needed to run Perfana, with a
Grafana instance that provisions just Perfana's own TimescaleDB data source. It does **not**
deploy metric backends (Prometheus/Loki/Tempo/Pyroscope), a system-under-test, or load-test
tooling. Add any further Grafana data sources from the Grafana UI after install.

---

## Table of contents

- [Installing Perfana on Windows Server 2025 (WSL2 + Docker Engine CE)](#installing-perfana-on-windows-server-2025-wsl2--docker-engine-ce)
  - [Table of contents](#table-of-contents)
  - [1. What gets deployed](#1-what-gets-deployed)
  - [2. Sizing \& prerequisites](#2-sizing--prerequisites)
  - [3. The dedicated share](#3-the-dedicated-share)
  - [4. Install WSL2 on Windows Server 2025](#4-install-wsl2-on-windows-server-2025)
  - [5. Allocate resources to WSL2 (`.wslconfig`)](#5-allocate-resources-to-wsl2-wslconfig)
  - [6. Prepare the dedicated share inside WSL](#6-prepare-the-dedicated-share-inside-wsl)
    - [Option A — dedicated ext4 VHDX (recommended)](#option-a--dedicated-ext4-vhdx-recommended)
    - [Option B — directory on the distro disk (simpler)](#option-b--directory-on-the-distro-disk-simpler)
  - [7. Install Docker Engine CE in WSL](#7-install-docker-engine-ce-in-wsl)
    - [7.1 Enable systemd](#71-enable-systemd)
    - [7.2 Install Docker CE from Docker's official repository](#72-install-docker-ce-from-dockers-official-repository)
    - [7.3 Enable and start Docker, allow your user to run it](#73-enable-and-start-docker-allow-your-user-to-run-it)
  - [8. Point Docker storage at the dedicated share](#8-point-docker-storage-at-the-dedicated-share)
  - [9. Deploy Perfana](#9-deploy-perfana)
    - [9.1 Get the deployment repository onto the share](#91-get-the-deployment-repository-onto-the-share)
    - [9.2 Configure `.env`](#92-configure-env)
    - [9.3 Start the stack](#93-start-the-stack)
    - [9.4 Run first-run bootstrap (once)](#94-run-first-run-bootstrap-once)
    - [9.5 Verify](#95-verify)
  - [10. Access Perfana](#10-access-perfana)
  - [11. Start automatically on boot](#11-start-automatically-on-boot)
  - [12. Backups](#12-backups)
  - [13. Upgrades](#13-upgrades)
  - [14. Troubleshooting](#14-troubleshooting)

---

## 1. What gets deployed

| Service | Image | Purpose | Browser port |
|---|---|---|---|
| `postgres` | timescale/timescaledb-ha:pg15 | Perfana + Keycloak + Grafana databases | 5432 (loopback) |
| `keycloak` | quay.io/keycloak/keycloak:24.0 | Authentication / SSO | 8080 |
| `perfana-migration` | perfana/perfana-migration | One-shot DB migrations | — |
| `perfana-api` | perfana/perfana-api | REST API (NestJS) | 3001 |
| `perfana-web` | perfana/perfana-web | UI (Next.js) | 4001 (`PERFANA_WEB_PORT`) |
| `perfana-worker` | perfana/perfana-worker | Analysis pipeline | — |
| `perfana-grafana-sync` | perfana/perfana-grafana-sync | Dashboard sync | — |
| `perfana-report` | perfana/perfana-report | PDF reports | — |
| `valkey` | valkey/valkey:8 | Job queue (Redis-compatible) | 6379 (loopback) |
| `grafana` | grafana/grafana:12.4 | Metric access for Perfana | 3100 (`GRAFANA_PORT`) |

Grafana provisions only Perfana's own TimescaleDB data source; add others from the Grafana UI.
PostgreSQL and Valkey are bound to `127.0.0.1` and are not reachable from the network.

---

## 2. Sizing & prerequisites

**Host (Windows Server 2025):**

- Windows Server 2025 (Standard or Datacenter), fully patched.
- Virtualization enabled in firmware (required for WSL2). On a VM, enable **nested
  virtualization** on the hypervisor.
- Local administrator rights.
- Outbound internet access (or a configured proxy / mirror) to pull Docker images from
  `quay.io`, `docker.io`, and `grafana.com` plugin CDN.

**Recommended resources** (this is a multi-service Java/Node + PostgreSQL stack):

| | Minimum | Recommended |
|---|---|---|
| vCPU | 4 | 8 |
| RAM | 12 GB | 16–24 GB |
| Disk (dedicated share) | 80 GB | 200 GB+ (grows with history) |

Of host RAM, reserve a few GB for Windows itself; the rest is given to WSL2 in
[step 5](#5-allocate-resources-to-wsl2-wslconfig).

**Network reachability the containers need (from inside WSL):**

- Outbound to the image registries listed above. Any extra Grafana data sources you add later
  must be reachable from inside WSL.

**Ports used on the server** (see [step 10](#10-access-perfana)): `4001` (UI, `PERFANA_WEB_PORT`),
`3001` (API), `8080` (Keycloak), `3100` (Grafana, `GRAFANA_PORT`). Accessed locally over
`http://localhost`; the UI and Grafana host ports are configurable in `.env`.

---

## 3. The dedicated share

This deployment keeps **all of its state on one dedicated storage location** — referred to here as
the *dedicated share*. That single location holds:

- the cloned deployment repository (`docker-compose.yml`, `.env`, config),
- all Docker **named volumes** (database, Keycloak, Grafana, Valkey) via Docker's `data-root`,
- pulled Docker images.

Keeping everything in one place makes the deployment easy to size, snapshot, and back up.

**Choose where the share lives — in order of preference:**

1. **A dedicated ext4 virtual disk (VHDX) mounted into WSL2** — *recommended.* Best performance,
   cleanly separated from the OS distro disk, easy to grow/snapshot at the Windows layer.
   Covered in [step 6](#6-prepare-the-dedicated-share-inside-wsl).
2. **A dedicated directory inside the WSL2 distro's own ext4 filesystem** (e.g. `/srv/perfana`).
   Simpler, acceptable for smaller installs; shares one virtual disk with the OS.

> ⚠️ **Do not** place the database / Docker data on a Windows path (`/mnt/c/...`) or on an
> **SMB / network share**. The Windows-interop filesystem (9P/DrvFs) and SMB do not provide the
> POSIX semantics and performance PostgreSQL needs — you will get poor performance and possible
> corruption. A network share is fine for **backup output** (see [step 12](#12-backups)), not for
> live data.

Throughout this guide the dedicated share is mounted at **`/srv/perfana`**. Adjust to taste.

---

## 4. Install WSL2 on Windows Server 2025

Open **PowerShell as Administrator**.

```powershell
# Installs the WSL2 platform + a default Ubuntu distro and sets WSL2 as default.
wsl --install -d Ubuntu-24.04

# If WSL was already present, make sure it is current:
wsl --update
wsl --set-default-version 2
```

Reboot if prompted. After reboot, launch **Ubuntu** from the Start menu once to create your
Linux user account (you will be asked for a UNIX username and password). Verify:

```powershell
wsl --status
wsl -l -v          # STATE should be "Running", VERSION "2"
```

> If `wsl --install` reports the feature is missing, enable the two Windows features, reboot, and
> retry:
> ```powershell
> dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
> dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
> ```

---

## 5. Allocate resources to WSL2 (`.wslconfig`)

WSL2 runs in a lightweight utility VM. By default it may take up to ~50% of host RAM and all
CPUs. **Pin explicit limits** so Perfana has guaranteed resources and Windows keeps headroom.

Create the file **`C:\Users\<your-admin-user>\.wslconfig`** (per-user, applies to the WSL2 VM).
A convenient way from PowerShell:

```powershell
notepad "$env:USERPROFILE\.wslconfig"
```

Recommended contents for a 24 GB / 8 vCPU host (scale to your hardware — leave a few GB and a
core or two for Windows):

```ini
[wsl2]
# CPU and memory granted to the WSL2 VM (and therefore to all containers).
processors=6
memory=20GB

# Swap on the WSL2 VM. Helps avoid OOM kills during PDF generation / analysis spikes.
swap=8GB

# Mirrored networking: WSL2 shares the host's network interfaces, so a container port
# published on 0.0.0.0 is reachable on the server's LAN IP without netsh portproxy rules
# (which otherwise break on every reboot because the NAT-mode WSL IP changes). Required if
# you expose PostgreSQL to other hosts — see step 9.6.
networkingMode=mirrored

# Reclaim unused RAM back to Windows over time (Windows 11/Server 2025).
[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
```


Apply the changes (this stops the VM; it restarts on next use):

```powershell
wsl --shutdown
```

Re-open Ubuntu and confirm the limits inside WSL:

```bash
nproc                       # should reflect "processors"
free -h                     # "Mem" total should reflect "memory"
```

> **Hypervisor scheduler.** WSL2 expects the *root* scheduler, and it's the default on current
> builds — but if this server has been hardened or specially configured, it's worth confirming
> `hypervisorschedulertype` is `root` (visible in the System event log / `bcdedit`), since the
> classic scheduler would change the contention dynamics.

---

## 6. Prepare the dedicated share inside WSL

### Option A — dedicated ext4 VHDX (recommended)

Create and attach a virtual disk that lives wherever you want the data on the Windows host
(e.g. a separate data drive `D:`).

**On the Windows host (PowerShell as Administrator):**

```powershell
# Create a 200 GB dynamically-expanding VHDX on the data drive.
$vhd = "G:\perfana\perfana-data.vhdx"
New-Item -ItemType Directory -Force -Path (Split-Path $vhd) | Out-Null
New-VHD -Path $vhd -Dynamic -SizeBytes 500GB

# Attach it into WSL (bare-mounts it for formatting/mounting in Linux).
wsl --mount --vhd $vhd --bare
```

**Inside WSL** (find the new disk, format it ext4, mount it):

```bash
lsblk                                   # identify the new device, e.g. /dev/sdc
sudo mkfs.ext4 -L perfana /dev/sdc      # format ONCE (destroys the disk's contents)
sudo mkdir -p /srv/perfana
sudo mount /dev/disk/by-label/perfana /srv/perfana
sudo chown -R "$USER":"$USER" /srv/perfana
```

Make the mount persistent across WSL restarts. Easiest is to let Windows attach the VHDX at WSL
start and mount by label via `/etc/fstab`:

```bash
sudo tee -a /etc/fstab >/dev/null <<'EOF'
LABEL=perfana  /srv/perfana  ext4  defaults,noatime  0  2
EOF
```

Then ensure the VHDX is attached whenever WSL starts. Add a Windows scheduled task (or include in
the startup task from [step 11](#11-start-automatically-on-boot)) that runs before the distro is
used:

```powershell
wsl --mount --vhd "D:\perfana\perfana-data.vhdx" --bare
```

> To re-attach after a host reboot manually: run the `wsl --mount --vhd ... --bare` command again,
> then `sudo mount -a` inside WSL.

### Option B — directory on the distro disk (simpler)

```bash
sudo mkdir -p /srv/perfana
sudo chown -R "$USER":"$USER" /srv/perfana
```

Either way you now have a writable `/srv/perfana` on the dedicated share.

---

## 7. Install Docker Engine CE in WSL

Run inside the Ubuntu (WSL) shell.

### 7.1 Enable systemd

Docker is managed by systemd. WSL2 supports systemd; enable it:

```bash
sudo tee /etc/wsl.conf >/dev/null <<'EOF'
[boot]
systemd=true
EOF
```

Restart WSL from **PowerShell** so systemd comes up:

```powershell
wsl --shutdown
```

Re-open Ubuntu, then confirm: `systemctl is-system-running` (expect `running` or `degraded`).

### 7.2 Install Docker CE from Docker's official repository

> Installing from Docker's official APT repository is the recommended method: you get the latest
> Engine + Compose v2 plugin, kept current by `apt upgrade`. Prefer it over Ubuntu's bundled
> `docker.io` package (older, no Compose v2) and over the `get.docker.com` convenience script
> (handy for throwaway setups, but Docker advises against it for production).

```bash
# Prereqs
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg jq git

# Docker's GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Engine + CLI + Compose plugin
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### 7.3 Enable and start Docker, allow your user to run it

```bash
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

Close and reopen the WSL shell (so the `docker` group applies), then verify:

```bash
docker version
docker compose version
docker run --rm hello-world
```

---

## 8. Point Docker storage at the dedicated share

So that **all images and volumes live on the dedicated share**, set Docker's `data-root`.
Do this **before** the first `start.sh` (moving it later means re-pulling images and losing
volumes).

```bash
sudo mkdir -p /srv/perfana/docker
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "data-root": "/srv/perfana/docker",
  "log-driver": "json-file",
  "log-opts": { "max-size": "20m", "max-file": "5" }
}
EOF

sudo systemctl restart docker
docker info --format '{{.DockerRootDir}}'    # must print /srv/perfana/docker
```

The `log-opts` cap container log growth so a chatty service can't fill the share.

---

## 9. Deploy Perfana

### 9.1 Get the deployment repository onto the share

```bash
cd /srv/perfana
git clone <your-repo-url> app        # or copy the deployment folder here
cd app
```

(If your organization mirrors this repo internally, clone from there. The deployment folder is
self-contained: `docker-compose.yml`, `.env.example`, the `start/stop/update/bootstrap` scripts,
and the `database/`, `keycloak/`, `grafana/`, `perfana/provisioning/` config directories.)

### 9.2 Configure `.env`

```bash
cp .env.example .env
```

Generate strong secrets:

```bash
openssl rand -base64 24   # for POSTGRES_PASSWORD, admin passwords
openssl rand -hex 32      # for ENCRYPTION_KEY and the client secrets
```

Edit `.env` and set **every** value. The important ones:

| Variable | Set to |
|---|---|
| `PERFANA_HOST` | `localhost` for this server-local deployment (the default). |
| `PERFANA_SCHEME` | `http` (the default; no TLS in this deployment). |
| `POSTGRES_PASSWORD` | Strong random value. |
| `KEYCLOAK_ADMIN_PASSWORD` | Strong random value (Keycloak console admin). |
| `ENCRYPTION_KEY` | 64-hex string. **Never change after first run.** |
| `KEYCLOAK_CLIENT_SECRET` / `KEYCLOAK_ADMIN_CLIENT_SECRET` / `GRAFANA_OAUTH_CLIENT_SECRET` | Random secrets; `bootstrap.sh` writes these into Keycloak. |
| `GRAFANA_ADMIN_PASSWORD` | Grafana break-glass admin password. |
| `PERFANA_ADMIN_USER` / `PERFANA_ADMIN_PASSWORD` | The initial Perfana admin login (`bootstrap.sh` sets the password). |

> `.env` contains secrets and is git-ignored. Keep its file permissions tight: `chmod 600 .env`.

### 9.3 Start the stack

```bash
./start.sh
```

This starts the database, runs migrations, starts Keycloak (waits until the realm is imported),
then starts the Perfana services and Grafana. Watch progress with `docker compose ps` and
`docker compose logs -f perfana-api`.

### 9.4 Run first-run bootstrap (once)

```bash
./bootstrap.sh
```

This aligns Keycloak to your `PERFANA_HOST`, sets the admin password, creates the Perfana
organization, applies the benchmark/dashboard provisioning, registers Grafana in Perfana, and
prints a **Perfana API key** (used by load generators to submit results — store it securely).

### 9.5 Verify

```bash
curl -fsS http://localhost:3001/api/health && echo OK    # API
curl -fsS http://localhost:3100/api/health && echo OK    # Grafana (GRAFANA_PORT)
docker compose ps                                        # all services Up/healthy
```

Then browse to `\<PERFANA_SCHEME\>://\<PERFANA_HOST\>:4001` and log in with `PERFANA_ADMIN_USER`.

### 9.6 Expose PostgreSQL to other hosts (optional)

By default PostgreSQL is published on `127.0.0.1:5432` and is **not** reachable from the network —
other hosts go through the Perfana API, not the database directly. Only do this if you have a
deliberate need (e.g. an external BI tool or a remote load generator querying the DB).

> ⚠️ This puts the database on the network. Auth is `scram-sha-256`, but scope the firewall rule
> to known source IPs and use a strong `POSTGRES_PASSWORD`.

This requires `networkingMode=mirrored` in `.wslconfig` ([step 5](#5-allocate-resources-to-wsl2-wslconfig)) —
in mirrored mode a `0.0.0.0` container bind is reachable on the server's LAN IP directly, with no
`netsh portproxy` rule to maintain.

1. **Publish the port on all interfaces** — in `docker-compose.yml`, drop the `127.0.0.1:` prefix
   from the `postgres` service:
   ```yaml
       ports:
         - "5432:5432"
   ```
   Re-apply with `./start.sh` (or `docker compose up -d postgres`).

2. **Open the Windows firewall**, scoped to the hosts that need access (PowerShell, as Administrator):
   ```powershell
   New-NetFirewallRule -DisplayName "Perfana Postgres 5432" -Direction Inbound `
     -Protocol TCP -LocalPort 5432 -Action Allow `
     -RemoteAddress 10.0.0.0/24       # <-- restrict to your client subnet
   ```

3. **Verify from another host:**
   ```powershell
   Test-NetConnection <THIS-SERVER-IP> -Port 5432   # TcpTestSucceeded : True
   ```

---

## 10. Access Perfana

This deployment is accessed over plain HTTP at **`http://localhost`**, from the server itself
(console or RDP session). WSL2 automatically forwards container ports published on `0.0.0.0` to
the Windows host's `localhost`, so once the stack is up you can browse on the server:

| Service | URL |
|---|---|
| Perfana UI | `http://localhost:4001` |
| Perfana API | `http://localhost:3001/api/health` |
| Keycloak | `http://localhost:8080` |
| Grafana | `http://localhost:3100` |

No firewall rules, port proxies, TLS, or reverse proxy are needed for this. `PERFANA_HOST=localhost`
and `PERFANA_SCHEME=http` are the defaults in `.env`.

> Exposing Perfana to other machines on the network, and adding TLS, are out of scope for this
> localhost deployment. If you ever need them, terminate TLS on a reverse proxy in front of the
> published ports, set `PERFANA_HOST`/`PERFANA_SCHEME` to the public name/scheme, and re-run
> `./stop.sh && ./start.sh && ./bootstrap.sh` so Keycloak redirect URIs and Grafana's root URL
> follow.

---

## 11. Start automatically on boot

WSL distros do not start until something invokes them. Combine three things:

1. **systemd** starts Docker inside WSL (already enabled in [step 7.1](#71-enable-systemd) via
   `systemctl enable docker`).
2. **Compose restart policy** (`restart: unless-stopped` on every long-running service) brings
   containers back once Docker is up.
3. **A Windows Scheduled Task** boots the distro (and re-attaches the VHDX) at system start.

Create the startup task (PowerShell as Administrator). Adjust the distro name, VHDX path, and
share path:

```powershell
$action = New-ScheduledTaskAction -Execute "wsl.exe" `
  -Argument "-d Ubuntu-24.04 -u root -e /srv/perfana/app/boot.sh"
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "Perfana" -Action $action -Trigger $trigger -Principal $principal
```

Create `boot.sh` on the share so the task has one entry point:

```bash
cat > /srv/perfana/app/boot.sh <<'EOF'
#!/usr/bin/env bash
set -e
mount -a 2>/dev/null || true          # mount the dedicated VHDX (Option A)
cd /srv/perfana/app
# Run as the owning user so the docker group applies:
sudo -u "$(stat -c '%U' /srv/perfana/app)" ./start.sh
EOF
chmod +x /srv/perfana/app/boot.sh
```

> If you use **VHDX (Option 6A)** add the `wsl --mount --vhd ... --bare` call as a *second*
> scheduled task triggered slightly earlier, or run it from the host side of the task before the
> distro starts.

Test it end-to-end with a host reboot before handing over.

---

## 12. Backups

Everything lives on the dedicated share, but the **database is the only thing you cannot
recreate**. Back it up with `pg_dump` and write the dump to a **network share** (mounting an SMB
share for *backup output* is fine — just not for live data).

```bash
# One-off
docker exec perfana-postgres pg_dump -U perfana -Fc perfana > /mnt/backup/perfana-$(date +%F).dump

# Restore (into a fresh, empty database)
cat /mnt/backup/perfana-YYYY-MM-DD.dump | \
  docker exec -i perfana-postgres pg_restore -U perfana -d perfana --clean --if-exists
```

Schedule the dump from cron inside WSL, or a Windows Scheduled Task that calls
`wsl -d Ubuntu-24.04 -e bash -lc '<dump command>'`. Also back up `.env` (it holds the
`ENCRYPTION_KEY`, without which stored secrets are unrecoverable) to a secure secrets store.

For a full point-in-time copy you can additionally snapshot the VHDX from the Windows host while
the stack is stopped (`./stop.sh`).

---

## 13. Upgrades

1. Back up the database (above).
2. Edit `docker-compose.yml` and bump the pinned `perfana/*` image tags (and Keycloak/Grafana if
   instructed in the release notes). Keep `perfana-migration` on the matching version.
3. Apply:

   ```bash
   ./update.sh
   ```

   This pulls images, re-runs migrations, and recreates changed services. The
   `ENCRYPTION_KEY` and named volumes are preserved.

4. Verify health as in [step 9.5](#95-verify).

---

## 14. Troubleshooting

| Symptom | Check |
|---|---|
| `start.sh`: "POSTGRES_PASSWORD must be set" | `.env` missing/empty value. All `${VAR:?}` vars are required. |
| Keycloak never becomes healthy | `docker compose logs keycloak`. Usually the DB isn't ready or the realm failed to import. |
| UI loads but login redirects fail / "invalid redirect URI" | Browse via `http://localhost` (not the machine name/IP). Keep `PERFANA_HOST=localhost`; if you changed it, run `./stop.sh && ./start.sh && ./bootstrap.sh`. |
| API rejects tokens ("issuer not accepted") | Browse via `http://localhost:8080` for Keycloak. The API accepts `keycloak:8080`, `localhost:8080`, and `<PERFANA_HOST>:8080`. |
| Grafana panels empty / "datasource not found" | Only the `postgres-timescaledb` data source is provisioned. Add any others (Prometheus/Loki/etc.) from the Grafana UI; ensure they're reachable from inside WSL. |
| Can't reach `http://localhost:<port>` on the server | Confirm the stack is up (`docker compose ps`) and the port matches `.env` (`PERFANA_WEB_PORT`/`GRAFANA_PORT`). WSL2 forwards published ports to the host's `localhost` automatically. |
| Postgres slow / disk errors | Data must be on ext4 (the dedicated share), **not** `/mnt/c` or SMB. Verify `docker info` `Docker Root Dir` = `/srv/perfana/docker`. |
| WSL using too much RAM | Tune `.wslconfig` ([step 5](#5-allocate-resources-to-wsl2-wslconfig)); `wsl --shutdown` to apply. |
| PDF report generation fails / OOM | `perfana-report` runs Chromium; ensure WSL `swap` is set and the host has free RAM. |
| Containers don't start after reboot | Confirm `systemctl is-enabled docker` = enabled, and the startup Scheduled Task ([step 11](#11-start-automatically-on-boot)) actually launched the distro. |

Useful commands:

```bash
docker compose ps                     # status of all services
docker compose logs -f <service>      # follow a service's logs
docker compose restart <service>      # restart one service
docker stats                          # live CPU/RAM per container
./stop.sh                             # stop (keep data)
./stop.sh --volumes                   # stop and DELETE all data (destructive)
```
