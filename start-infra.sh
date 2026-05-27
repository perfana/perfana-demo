#!/bin/bash
# ================================================================================================
# Perfana Infrastructure Start Script
# ================================================================================================
# Starts all infrastructure services for local development.
# Perfana services (api, web, worker, grafana-sync) should be run on the host via `npm run dev`.
#
# Prerequisites:
#   - Docker and Docker Compose installed
# ================================================================================================

set -o pipefail
set -o nounset

COMPOSE_FILE="docker-compose.yml"

# Set environment variables with defaults
export SUT_VERSION=${SUT_VERSION:-2.4.3-good-baseline}
export POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-perfana}
export KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN:-admin}
export KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD:-admin}

echo "Starting Perfana Infrastructure..."
echo ""

# Start core infrastructure first
echo "[1/6] Starting core databases..."
docker compose -f "$COMPOSE_FILE" up -d postgres redis mariadb influxdb pgbouncer

# Run database migrations (waits for postgres healthy, then exits)
echo "[2/6] Running database migrations..."
docker compose -f "$COMPOSE_FILE" up perfana-migration
MIGRATION_EXIT=$?
if [ $MIGRATION_EXIT -ne 0 ]; then
  echo "WARNING: Database migration failed (exit code $MIGRATION_EXIT). Check logs:"
  echo "  docker compose -f $COMPOSE_FILE logs perfana-migration"
fi

# Wait for postgres to be healthy before starting keycloak
echo "[3/6] Starting authentication..."
docker compose -f "$COMPOSE_FILE" up -d keycloak-theme-provider
docker compose -f "$COMPOSE_FILE" up -d keycloak

# Wait for Keycloak to be healthy, then ensure test user password is set
echo "       Waiting for Keycloak..."
for i in $(seq 1 30); do
  kc_status=$(docker compose -f "$COMPOSE_FILE" ps keycloak --format "{{.Status}}" 2>/dev/null)
  if echo "$kc_status" | grep -q "healthy"; then
    break
  fi
  sleep 2
done
docker exec perfana-keycloak /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 --realm master --user "${KEYCLOAK_ADMIN}" --password "${KEYCLOAK_ADMIN_PASSWORD}" 2>/dev/null
docker exec perfana-keycloak /opt/keycloak/bin/kcadm.sh set-password \
  -r perfana-prod --username "admin@perfana.io" --new-password "Perfana1!" 2>/dev/null \
  && echo "       Test user ready: admin@perfana.io / Perfana1!" \
  || echo "       WARNING: Could not set test user password"

# Start observability stack
echo "[4/6] Starting observability stack..."
docker compose -f "$COMPOSE_FILE" up -d grafana prometheus alertmanager tempo pyroscope loki telegraf

# Start demo applications
echo "[5/6] Starting demo applications..."
docker compose -f "$COMPOSE_FILE" up -d afterburner-fe afterburner-be wiremock

# Start mock services and load testing
echo "[6/6] Starting load testing..."
docker compose -f "$COMPOSE_FILE" up -d loadtest jmetertest

echo ""
echo "Infrastructure started!"
echo ""
echo "Core Services:"
echo "  PostgreSQL:            localhost:5432"
echo "  PgBouncer:             localhost:6432"
echo "  Redis:                 localhost:6379"
echo "  Keycloak:              http://localhost:8080  (admin/admin)"
echo "  Grafana:               http://localhost:3000  (perfana/perfana)"
echo ""
echo "Observability:"
echo "  Prometheus:            http://localhost:9090"
echo "  Alertmanager:          http://localhost:9093"
echo "  Tempo (Tracing):       http://localhost:3200"
echo "  Pyroscope (Profiling): http://localhost:4040"
echo "  Loki (Logs):           http://localhost:3100"
echo ""
echo "Demo Applications:"
echo "  Afterburner Frontend:  http://localhost:8090"
echo "  MariaDB:               localhost:3306"
echo "  InfluxDB:              http://localhost:8086"
echo "  Wiremock:              http://localhost:8060"
echo ""
echo "Perfana services NOT started (run locally):"
echo "  npm run dev:api          -> http://localhost:3001"
echo "  npm run dev:web          -> http://localhost:4001"
echo "  npm run dev:grafana-sync"
echo "  npm run dev              -> all services"
echo ""
echo "Commands:"
echo "  docker compose -f $COMPOSE_FILE ps      # Check status"
echo "  docker compose -f $COMPOSE_FILE logs -f  # View logs"
echo ""
