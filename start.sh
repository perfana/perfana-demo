#!/bin/bash
# ================================================================================================
# Perfana Quick Start Script
# ================================================================================================
# Starts all services (infrastructure + Perfana) for an already-initialized environment.
# For first-time setup, use init-demo.sh instead.
#
# Prerequisites:
#   - Docker and Docker Compose installed
#   - Environment previously initialized with init-demo.sh
# ================================================================================================

set -o pipefail
set -o nounset

COMPOSE_FILE="docker-compose.yml"

# Set environment variables with defaults
export SUT_VERSION=${SUT_VERSION:-2.4.3-good-baseline}
export POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-perfana}
export KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN:-admin}
export KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD:-admin}

echo "Starting Perfana Services..."
echo ""

# Start core infrastructure first
echo "[1/7] Starting core databases..."
docker compose -f "$COMPOSE_FILE" up -d postgres redis mariadb influxdb

# Run database migrations (waits for postgres healthy, then exits)
echo "[2/7] Running database migrations..."
docker compose -f "$COMPOSE_FILE" up perfana-migration
MIGRATION_EXIT=$?
if [ $MIGRATION_EXIT -ne 0 ]; then
  echo "WARNING: Database migration failed (exit code $MIGRATION_EXIT). Check logs:"
  echo "  docker compose -f $COMPOSE_FILE logs perfana-migration"
fi

# Start authentication
echo "[3/7] Starting authentication..."
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

# Start Perfana services
echo "[4/7] Starting Perfana services..."
docker compose -f "$COMPOSE_FILE" up -d perfana-api perfana-web perfana-worker perfana-grafana-sync perfana-snapshot perfana-report

# Start observability stack
echo "[5/7] Starting observability stack..."
docker compose -f "$COMPOSE_FILE" up -d grafana prometheus alertmanager tempo pyroscope loki telegraf

# Start demo applications
echo "[6/7] Starting demo applications..."
docker compose -f "$COMPOSE_FILE" up -d afterburner-fe afterburner-be wiremock

# Start load testing
echo "[7/7] Starting load testing..."
docker compose -f "$COMPOSE_FILE" up -d loadtest jmetertest

echo ""
echo "All services started!"
echo ""
echo "Core Services:"
echo "  PostgreSQL:            localhost:5432"
echo "  Redis:                 localhost:6379"
echo "  Keycloak:              http://localhost:8080  (admin/admin)"
echo "  Perfana Web:           http://localhost:4000"
echo "  Perfana API:           http://localhost:3001"
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
echo "Commands:"
echo "  docker compose -f $COMPOSE_FILE ps      # Check status"
echo "  docker compose -f $COMPOSE_FILE logs -f  # View logs"
echo ""
