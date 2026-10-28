#!/usr/bin/env bash
# ==================================================================================================
# Perfana - start
# --------------------------------------------------------------------------------------------------
# Brings the stack up in the correct order:
#   1. PostgreSQL + Valkey
#   2. Database migrations (one-shot, must finish before the API starts)
#   3. Keycloak (waits until healthy = realm imported)
#   4. Perfana services + Grafana
#
# Run inside WSL2 from the deployment directory. Requires a populated .env.
# For first-time integration setup, run ./bootstrap.sh after this succeeds.
# ==================================================================================================
set -euo pipefail
cd "$(dirname "$0")"

# Container runtime. Podman by default; override to run the same scripts under
# Docker:  CONTAINER_CLI=docker COMPOSE="docker compose" ./start.sh
CONTAINER_CLI=(${CONTAINER_CLI:-podman})
COMPOSE=(${COMPOSE:-podman compose})

# Grafana is optional (see docker-compose.yml). It is in the "grafana" compose
# profile, switched on with COMPOSE_PROFILES=grafana in .env.
grafana_enabled() { [[ ",${COMPOSE_PROFILES:-}," == *,grafana,* ]]; }

if [[ ! -f .env ]]; then
  echo "ERROR: .env not found. Copy .env.example to .env and fill it in first." >&2
  exit 1
fi
# Load .env for the messages below (podman compose reads .env on its own).
set -a; . ./.env; set +a

echo "[1/4] Starting database and queue..."
"${COMPOSE[@]}" up -d postgres valkey

echo "[2/4] Running database migrations..."
if ! "${COMPOSE[@]}" run --rm perfana-migration; then
  echo "WARNING: migration runner exited non-zero. Check: podman compose logs perfana-migration" >&2
fi

echo "[3/4] Starting Keycloak (waiting until healthy)..."
"${COMPOSE[@]}" up -d keycloak
for i in $(seq 1 40); do
  status="$("${COMPOSE[@]}" ps keycloak --format '{{.Status}}' 2>/dev/null || true)"
  if echo "$status" | grep -q healthy; then echo "       Keycloak healthy."; break; fi
  if [[ "$i" -eq 40 ]]; then echo "       WARNING: Keycloak not healthy after ~5 min."; fi
  sleep 8
done

echo "[4/4] Starting Perfana services..."
"${COMPOSE[@]}" up -d perfana-api perfana-web perfana-worker perfana-report
if grafana_enabled; then
  echo "       Grafana profile active — starting grafana and perfana-grafana-sync."
  "${COMPOSE[@]}" --profile grafana up -d grafana perfana-grafana-sync
fi

scheme="${PERFANA_SCHEME:-http}"; host="${PERFANA_HOST:-localhost}"
web_port="${PERFANA_WEB_PORT:-4001}"; grafana_port="${GRAFANA_PORT:-3100}"
cat <<EOF

Perfana is starting. Endpoints (browser-facing):
  Perfana UI :  ${scheme}://${host}:${web_port}
  Perfana API:  ${scheme}://${host}:3001/api/health
  Keycloak   :  ${scheme}://${host}:8080

Status : podman compose ps
Logs   : podman compose logs -f <service>
First-run integration setup: ./bootstrap.sh
EOF

if grafana_enabled; then
  echo "  Grafana    :  ${scheme}://${host}:${grafana_port}"
else
  echo "Grafana is disabled. Enable it with COMPOSE_PROFILES=grafana in .env, then re-run ./start.sh."
fi
