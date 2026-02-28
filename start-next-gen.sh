#!/bin/bash
# ================================================================================================
# Perfana Next-Gen Quick Start Script
# ================================================================================================
# This script starts all Perfana next-gen services using docker-compose.
# Unlike init-demo-next-gen.sh, this assumes the environment is already initialized
# and simply starts all services.
#
# Architecture: ARM64 (Apple Silicon M1/M2) with Node.js 20.19.5
# Images: Using version 0.1.0 ARM64 builds
# ================================================================================================

set -o errexit
set -o pipefail
set -o nounset

# Generate required environment variables
export SUT_VERSION=${SUT_VERSION:-2.4.3-good-baseline}
export GIT_SHA=${GIT_SHA:-c3ee4b9}
export POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-perfana}
export KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN:-admin}
export KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD:-admin}

echo "🚀 Starting Perfana Next-Gen Services..."
echo ""

# Start infrastructure services
echo "Starting infrastructure services..."
docker compose -f docker-compose-next-gen.yml up -d postgres
docker compose -f docker-compose-next-gen.yml up -d redis
docker compose -f docker-compose-next-gen.yml up -d keycloak
docker compose -f docker-compose-next-gen.yml up -d mariadb
docker compose -f docker-compose-next-gen.yml up -d influxdb

# Start monitoring and observability
echo "Starting observability stack..."
docker compose -f docker-compose-next-gen.yml up -d grafana
docker compose -f docker-compose-next-gen.yml up -d prometheus
docker compose -f docker-compose-next-gen.yml up -d alertmanager
docker compose -f docker-compose-next-gen.yml up -d tempo
docker compose -f docker-compose-next-gen.yml up -d pyroscope
docker compose -f docker-compose-next-gen.yml up -d loki
docker compose -f docker-compose-next-gen.yml up -d telegraf

# Start Perfana next-gen services
echo "Starting Perfana next-gen services..."
docker compose -f docker-compose-next-gen.yml up -d perfana-api
docker compose -f docker-compose-next-gen.yml up -d perfana-web
docker compose -f docker-compose-next-gen.yml up -d perfana-worker
docker compose -f docker-compose-next-gen.yml up -d perfana-grafana-sync
docker compose -f docker-compose-next-gen.yml up -d perfana-snapshot

# Start demo application
echo "Starting demo applications..."
docker compose -f docker-compose-next-gen.yml up -d afterburner-fe
docker compose -f docker-compose-next-gen.yml up -d afterburner-be
docker compose -f docker-compose-next-gen.yml up -d wiremock

# Start load test environment
echo "Starting load test environment..."
docker compose -f docker-compose-next-gen.yml up -d loadtest
docker compose -f docker-compose-next-gen.yml up -d jmetertest

echo ""
echo "✅ All services started!"
echo ""
echo "Platform: ARM64 (Apple Silicon M1/M2) - Node.js 20.19.5"
echo "Images: perfana/perfana-*:0.1.0"
echo ""
echo "Key Services:"
echo "  • Perfana Web (Next.js):     http://localhost:4002"
echo "  • Perfana API (NestJS):      http://localhost:3001"
echo "  • Keycloak (Auth):           http://localhost:8080"
echo "  • PostgreSQL (Database):     localhost:5432"
echo "  • Grafana:                   http://localhost:3000"
echo "  • Redis (Job Queue):         localhost:6379"
echo ""
echo "Application Services:"
echo "  • Afterburner Frontend:      http://localhost:8090"
echo "  • MariaDB:                   localhost:3306"
echo "  • InfluxDB:                  http://localhost:8086"
echo ""
echo "Observability:"
echo "  • Prometheus:                http://localhost:9090"
echo "  • Tempo (Tracing):           http://localhost:3200"
echo "  • Pyroscope (Profiling):     http://localhost:4040"
echo "  • Loki (Logs):               http://localhost:3100"
echo "  • Alertmanager:              http://localhost:9093"
echo ""
echo "Use 'docker compose -f docker-compose-next-gen.yml ps' to check status"
echo "Use 'docker compose -f docker-compose-next-gen.yml logs -f [service]' to view logs"
echo ""
