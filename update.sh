#!/usr/bin/env bash
# ==================================================================================================
# Perfana - update
# --------------------------------------------------------------------------------------------------
# Upgrades to the image versions pinned in docker-compose.yml:
#   1. Pull updated images
#   2. Re-run database migrations
#   3. Recreate changed services
#
# Pin image tags by editing docker-compose.yml before running this. Back up the
# database first (see INSTALL.md "Backups").
# ==================================================================================================
set -euo pipefail
cd "$(dirname "$0")"

# Container runtime. Podman by default; override to run the same scripts under
# Docker:  CONTAINER_CLI=docker COMPOSE="docker compose" ./start.sh
CONTAINER_CLI=(${CONTAINER_CLI:-podman})
COMPOSE=(${COMPOSE:-podman-compose})

# Grafana is optional (the "grafana" compose profile in docker-compose.yml).
grafana_enabled() { [[ ",${COMPOSE_PROFILES:-}," == *,grafana,* ]]; }

if [[ ! -f .env ]]; then
  echo "ERROR: .env not found." >&2
  exit 1
fi

echo "[1/3] Pulling images..."
"${COMPOSE[@]}" pull

echo "[2/3] Running database migrations..."
"${COMPOSE[@]}" up -d postgres valkey
# Same reason as in start.sh: ordering is enforced here, not by depends_on.
for ((i = 1; i <= 40; i++)); do
  [[ "$("${CONTAINER_CLI[@]}" inspect -f '{{.State.Health.Status}}' perfana-postgres 2>/dev/null || true)" == "healthy" ]] && break
  [[ $i -eq 40 ]] && { echo "ERROR: PostgreSQL not healthy; aborting before migrations." >&2; exit 1; }
  sleep 8
done
if ! "${COMPOSE[@]}" run --rm perfana-migration; then
  echo "WARNING: migration runner exited non-zero. Check: podman-compose logs perfana-migration" >&2
fi

echo "[3/3] Recreating services..."
# Services are named explicitly rather than using a bare `up -d`: that way the
# optional profiles stay off even if the compose implementation ignores
# `profiles:` in docker-compose.yml.
"${COMPOSE[@]}" up -d postgres valkey keycloak \
  perfana-api perfana-web perfana-worker perfana-report \
  docker-socket-proxy valkey-monitor docker-monitor libredb
if grafana_enabled; then
  "${COMPOSE[@]}" --profile grafana up -d grafana perfana-grafana-sync
fi

echo "Done. Verify: podman-compose ps"
