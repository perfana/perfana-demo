#!/bin/bash
# ================================================================================================
# Perfana Next-Gen Demo Initialization Script
# ================================================================================================
# First-time setup for the full Perfana next-gen demo environment.
# Starts all infrastructure + Perfana services, creates an API key,
# and runs baseline load tests.
#
# Prerequisites:
#   - Docker and Docker Compose installed
#   - jq installed (for API key extraction)
# ================================================================================================

set -o pipefail
set -o nounset

COMPOSE_FILE="docker-compose-next-gen.yml"

# Set environment variables with defaults
export SUT_VERSION=${SUT_VERSION:-2.4.3-good-baseline}
export POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-perfana}
export KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN:-admin}
export KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD:-admin}

echo "Initializing Perfana Next-Gen Demo Environment..."
echo ""

# Start core infrastructure first
echo "[1/8] Starting core databases..."
docker compose -f "$COMPOSE_FILE" up -d postgres redis mariadb influxdb

# Run database migrations (waits for postgres healthy, then exits)
echo "[2/8] Running database migrations..."
docker compose -f "$COMPOSE_FILE" up perfana-migration
MIGRATION_EXIT=$?
if [ $MIGRATION_EXIT -ne 0 ]; then
  echo "WARNING: Database migration failed (exit code $MIGRATION_EXIT). Check logs:"
  echo "  docker compose -f $COMPOSE_FILE logs perfana-migration"
fi

# Start authentication
echo "[3/8] Starting authentication..."
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
  -r perfana-prod --username "perfana@example.com" --new-password "Perfana1!" 2>/dev/null \
  && echo "       Test user ready: perfana@example.com / Perfana1!" \
  || echo "       WARNING: Could not set test user password"

# Start Perfana services
echo "[4/8] Starting Perfana services..."
docker compose -f "$COMPOSE_FILE" up -d perfana-api
docker compose -f "$COMPOSE_FILE" up -d perfana-web
docker compose -f "$COMPOSE_FILE" up -d perfana-worker
docker compose -f "$COMPOSE_FILE" up -d perfana-grafana-sync
docker compose -f "$COMPOSE_FILE" up -d perfana-snapshot
docker compose -f "$COMPOSE_FILE" up -d perfana-report

# Start observability stack
echo "[5/8] Starting observability stack..."
docker compose -f "$COMPOSE_FILE" up -d grafana prometheus alertmanager tempo pyroscope loki telegraf

# Start demo applications
echo "[6/8] Starting demo applications..."
docker compose -f "$COMPOSE_FILE" up -d afterburner-fe afterburner-be wiremock

# Start mock services and load testing
echo "[7/8] Starting mock services and load testing..."
docker compose -f "$COMPOSE_FILE" up -d dynatrace-saas-mock dynatrace-managed-mock
docker compose -f "$COMPOSE_FILE" up -d loadtest jmetertest

# Wait for Perfana API and create API key
echo "[8/8] Waiting for Perfana API and creating API key..."
echo "       Waiting for Perfana API to be ready..."
for i in $(seq 1 60); do
  if curl -sf http://localhost:3001/api/health > /dev/null 2>&1; then
    echo "       Perfana API is ready."
    break
  fi
  sleep 2
done

echo "       Creating API key..."
api_key=$(curl -sf --location 'http://localhost:3001/api/key' \
  --header 'Content-Type: application/json' \
  --data '{
    "validFor": "1y",
    "description": "demo"
  }' | jq -r '.key.data' 2>/dev/null)

if [ -n "$api_key" ] && [ "$api_key" != "null" ]; then
  sed -i.bak "s/__apiKey__/$api_key/" ./loadtest/pom.xml && rm -f ./loadtest/pom.xml.bak
  echo "       API key injected into loadtest/pom.xml"
else
  echo "       WARNING: Could not create API key. You may need to configure it manually."
fi

echo ""
echo "Running 3 baseline load tests..."
./deploy-and-test-jmeter.sh baseline
./deploy-and-test-jmeter.sh baseline
./deploy-and-test-jmeter.sh baseline

echo ""
echo "Perfana Next-Gen Demo Environment Ready!"
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
echo "Mock Services:"
echo "  Dynatrace SaaS Mock:     http://localhost:8092"
echo "  Dynatrace Managed Mock:  http://localhost:8091"
echo ""
echo "Commands:"
echo "  docker compose -f $COMPOSE_FILE ps      # Check status"
echo "  docker compose -f $COMPOSE_FILE logs -f  # View logs"
echo ""
