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

if [[ ! -f .env ]]; then
  echo "ERROR: .env not found. Copy .env.example to .env and fill it in first." >&2
  exit 1
fi
# Load .env for the messages below (docker compose reads .env on its own).
set -a; . ./.env; set +a

echo "[1/4] Starting database and queue..."
docker compose up -d postgres valkey

echo "[2/4] Running database migrations..."
if ! docker compose run --rm perfana-migration; then
  echo "WARNING: migration runner exited non-zero. Check: docker compose logs perfana-migration" >&2
fi

echo "[3/4] Starting Keycloak (waiting until healthy)..."
docker compose up -d keycloak
for i in $(seq 1 40); do
  status="$(docker compose ps keycloak --format '{{.Status}}' 2>/dev/null || true)"
  if echo "$status" | grep -q healthy; then echo "       Keycloak healthy."; break; fi
  if [[ "$i" -eq 40 ]]; then echo "       WARNING: Keycloak not healthy after ~5 min."; fi
  sleep 8
done

echo "[4/4] Starting Perfana services and Grafana..."
docker compose up -d perfana-api perfana-web perfana-worker perfana-grafana-sync perfana-report grafana

scheme="${PERFANA_SCHEME:-http}"; host="${PERFANA_HOST:-localhost}"
web_port="${PERFANA_WEB_PORT:-4001}"; grafana_port="${GRAFANA_PORT:-3100}"
cat <<EOF

Perfana is starting. Endpoints (browser-facing):
  Perfana UI :  ${scheme}://${host}:${web_port}
  Perfana API:  ${scheme}://${host}:3001/api/health
  Keycloak   :  ${scheme}://${host}:8080
  Grafana    :  ${scheme}://${host}:${grafana_port}

Status : docker compose ps
Logs   : docker compose logs -f <service>
First-run integration setup: ./bootstrap.sh
EOF
