#!/bin/bash
# ================================================================================================
# Perfana Next-Gen Demo Initialization Script
# ================================================================================================
# This script initializes the Perfana next-gen demo environment with:
# - PostgreSQL database (TimescaleDB)
# - Keycloak authentication server
# - Next-Gen Perfana services (perfana-web, perfana-api, perfana-worker, perfana-grafana-sync)
# - Observability stack (Grafana, Prometheus, Tempo, Pyroscope, Loki)
# - Afterburner demo application
#
# Architecture: ARM64 (Apple Silicon M1/M2) with Node.js 20.19.5
# Images: Using version 0.1.0 ARM64 builds
# - perfana/perfana-web:0.1.0
# - perfana/perfana-api:0.1.0
# - perfana/perfana-worker:0.1.0
# - perfana/perfana-grafana-sync:0.1.0
# ================================================================================================

set -o errexit
set -o pipefail
set -o nounset

source common.sh

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  key="$1"

  case "$key" in
    -s|--sleep)
    SLEEP_TIME="$2"
    shift # past argument
    shift # past value
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
  esac
done
set -- "${POSITIONAL[@]-default}" # restore positional parameters

export SUT_VERSION=2.4.3-good-baseline
export GIT_SHA=c3ee4b9

# Generate required environment variables for next-gen stack
export POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-perfana}
export KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN:-admin}
export KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD:-admin}

SLEEP_TIME=${SLEEP_TIME:-15}
echo "using sleep time of $SLEEP_TIME seconds, use -s or --sleep option to change"

echo "Starting PostgreSQL database (TimescaleDB) ..."
docker-compose -f docker-compose-next-gen.yml up -d postgres

echo "Sleeping for $SLEEP_TIME secs to give PostgreSQL time to start up..."
sleep $SLEEP_TIME

echo "Starting Keycloak authentication server ..."
docker-compose -f docker-compose-next-gen.yml up -d keycloak

echo "Starting Redis for BullMQ job queue ..."
docker-compose -f docker-compose-next-gen.yml up -d redis

echo "Bringing up databases that need time to start up..."
docker-compose -f docker-compose-next-gen.yml up -d mariadb
docker-compose -f docker-compose-next-gen.yml up -d influxdb

echo "Sleeping for $SLEEP_TIME secs to give Keycloak and databases time to start up..."
sleep $SLEEP_TIME

echo "Starting Grafana ..."
docker-compose -f docker-compose-next-gen.yml up -d grafana

echo "Sleeping for $SLEEP_TIME secs to give Grafana some time to start up..."
sleep $SLEEP_TIME

echo "Starting Next-Gen Perfana API (NestJS) ..."
docker-compose -f docker-compose-next-gen.yml up -d perfana-api

echo "Starting Next-Gen Perfana Web (Next.js) ..."
docker-compose -f docker-compose-next-gen.yml up -d perfana-web

echo "Sleeping for $SLEEP_TIME secs to give Perfana next-gen services a chance to start up..."
sleep $SLEEP_TIME

echo "Starting Perfana data processing services ..."
docker-compose -f docker-compose-next-gen.yml up -d perfana-grafana-sync
docker-compose -f docker-compose-next-gen.yml up -d perfana-snapshot
docker-compose -f docker-compose-next-gen.yml up -d perfana-worker

echo "Starting observability stack ..."
docker-compose -f docker-compose-next-gen.yml up -d telegraf
docker-compose -f docker-compose-next-gen.yml up -d prometheus
docker-compose -f docker-compose-next-gen.yml up -d alertmanager
docker-compose -f docker-compose-next-gen.yml up -d tempo
docker-compose -f docker-compose-next-gen.yml up -d pyroscope
docker-compose -f docker-compose-next-gen.yml up -d loki

echo "Sleeping for $SLEEP_TIME secs to give containers a chance to start up..."
sleep $SLEEP_TIME

echo "Starting afterburner applications ..."
docker-compose -f docker-compose-next-gen.yml up -d afterburner-fe
docker-compose -f docker-compose-next-gen.yml up -d afterburner-be

echo "Sleeping for $SLEEP_TIME secs to give afterburners a chance to start up..."
sleep $SLEEP_TIME

echo "Starting loadtest environment ..."
docker-compose -f docker-compose-next-gen.yml up -d loadtest

echo "Waiting for PostgreSQL to be ready..."
until docker-compose -f docker-compose-next-gen.yml exec -T postgres pg_isready -U perfana -d perfana_native > /dev/null 2>&1; do
    echo "Waiting for PostgreSQL database to start..."
    sleep 2
done

echo "Waiting for Keycloak to be ready..."
until curl -f http://localhost:8080/health/ready > /dev/null 2>&1; do
    echo "Waiting for Keycloak to start..."
    sleep 2
done

echo "Waiting for Perfana API to be ready..."
echo "Sleeping for 30 seconds to allow Perfana API to fully start..."
sleep 30

# Fetch the API key from the new NestJS API
echo "Creating API key via new Perfana API..."
api_key=$(curl --location 'http://localhost:3001/api/key' \
             --header 'Content-Type: application/json' \
             --user 'perfana:perfana' \
             --data '{
                 "validFor": "1y",
                 "description": "demo"
             }' | jq -r '.key.data')

# Replace __apiKey__ in ./loadtest/pom.xml with the fetched API key
# Cross-platform sed command using shared function
cross_platform_sed "s/__apiKey__/$api_key/" ./loadtest/pom.xml

echo "Environment Variables for Next-Gen Stack:"
echo "=========================================="
echo "POSTGRES_PASSWORD: $POSTGRES_PASSWORD"
echo "PostgreSQL: localhost:5432"
echo "Next-Gen Perfana Web: http://localhost:4002"
echo "Next-Gen Perfana API: http://localhost:3001"
echo "Keycloak: http://localhost:8080"
echo "Grafana: http://localhost:3000"
echo "=========================================="

echo "Running 3 baseline load tests with SUT_VERSION=${SUT_VERSION} and GIT_SHA=${GIT_SHA}"
./deploy-and-test.sh baseline
./deploy-and-test.sh baseline
./deploy-and-test.sh baseline
echo "Next-Gen Perfana Demo Environment Ready!"

echo ""
echo "🚀 Next-Gen Perfana Stack is now running!"
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