#!/usr/bin/env bash
set -o pipefail
set -o nounset

if [ $# -ne 1 ]; then
  echo "Supply one option: 'baseline', 'cpu', 'backend', 'pool', or 'custom'."
  exit 1
fi

# Function to restart afterburner services
COMPOSE_FILE="docker-compose.yml"

restart_afterburner() {
    docker compose -f "$COMPOSE_FILE" stop afterburner-fe
    docker compose -f "$COMPOSE_FILE" stop afterburner-be
    docker compose -f "$COMPOSE_FILE" rm -f afterburner-fe
    docker compose -f "$COMPOSE_FILE" rm -f afterburner-be
    docker compose -f "$COMPOSE_FILE" up -d afterburner-fe
    docker compose -f "$COMPOSE_FILE" up -d afterburner-be
}

while (( "$#" )); do
  case "$1" in
    baseline)
      echo "Deploying and testing baseline (JMeter Webshop tests in parallel)."
      export SUT_VERSION=2.4.3-good-baseline
      export GIT_SHA=4e2db5f
      export ANNOTATIONS="Proxy Dev: make cpu more efficient"
      export JMETER_TEST="webshop-*.jmx"
      restart_afterburner
      break
    ;;
    backend)
      echo "Deploying and testing image with backend calls issue (JMeter Webshop tests in parallel)."
      export SUT_VERSION=2.4.3-increased-backend-calls
      export GIT_SHA=a2d09ca
      export ANNOTATIONS="Proxy Dev: Accidentally triple the amount of back end calls"
      export JMETER_TEST="webshop-*.jmx"
      restart_afterburner
      break
    ;;
    cpu)
      echo "Deploying and testing baseline with cpu issue (JMeter Webshop tests in parallel)."
      export SUT_VERSION=2.4.3-changed-matrix-calc
      export GIT_SHA=26361d2
      export ANNOTATIONS="Proxy Dev: make matrix calculation more variable"
      export JMETER_TEST="webshop-*.jmx"
      restart_afterburner
      break
    ;;
    pool)
      echo "Deploying and testing version with connection pool issue (JMeter Webshop tests in parallel)."
      export SUT_VERSION=2.4.3-default-http-conn-pool
      export GIT_SHA=19b60ef
      export ANNOTATIONS="Proxy Dev: use default httpclient connection pool size"
      export JMETER_TEST="webshop-*.jmx"
      restart_afterburner
      break
    ;;
    custom)
      if [ -z "${SUT_VERSION:-}" ]; then
        echo "Error: SUT_VERSION must be set when using 'custom'." >&2
        echo "Example: SUT_VERSION=abc1234-jdk21 ./deploy-and-test-jmeter.sh custom" >&2
        exit 1
      fi
      echo "Deploying and testing custom build: ${SUT_VERSION}"
      export GIT_SHA="${GIT_SHA:-$(git -C "${AFTERBURNER_PATH:-$HOME/workspace/afterburner}" rev-parse --short HEAD 2>/dev/null || echo "unknown")}"
      export ANNOTATIONS="${ANNOTATIONS:-Local dev build: ${SUT_VERSION}}"
      export JMETER_TEST="${JMETER_TEST:-webshop-*.jmx}"
      restart_afterburner
      break
    ;;
    *)
      echo "Error: Unsupported parameter '$1'" >&2
      echo "Valid options are: 'baseline', 'cpu', 'backend', 'pool', and 'custom'."
      exit 1
      shift
      break
    ;;
  esac
done

# wait for services to be healthy
echo "Waiting for services to be ready..."
wait_for_service() {
    local service=$1
    local max_attempts=30  # 2 minutes timeout (30 * 4 seconds)
    local attempt=1

    echo "Waiting for $service to be healthy..."
    while [ $attempt -le $max_attempts ]; do
        if docker compose -f "$COMPOSE_FILE" ps "$service" | grep -q "Up"; then
            echo "$service is healthy!"
            return 0
        fi
        echo "Attempt $attempt/$max_attempts: $service not ready yet..."
        sleep 4
        attempt=$((attempt + 1))
    done
    echo "Timeout waiting for $service to become healthy"
    return 1
}

if ! wait_for_service "afterburner-fe"; then
    echo "Frontend service failed to become healthy"
    exit 1
fi

if ! wait_for_service "afterburner-be"; then
    echo "Backend service failed to become healthy"
    exit 1
fi

# Restart jmetertest container to ensure clean state
echo "Restarting jmetertest container..."
docker compose -f "$COMPOSE_FILE" down jmetertest
docker compose -f "$COMPOSE_FILE" up -d --build jmetertest

# Wait for jmetertest container to be ready
if ! wait_for_service "jmetertest"; then
    echo "JMeter test container failed to become healthy"
    exit 1
fi

# Create output directories
docker compose -f "$COMPOSE_FILE" exec jmetertest mkdir -p /tests/target/results /tests/target/reports

# Run JMeter tests via perfana-cli
echo "Running JMeter load test: ${JMETER_TEST} with SUT_VERSION=${SUT_VERSION}"
docker compose -f "$COMPOSE_FILE" exec \
  -e SUT_VERSION="${SUT_VERSION}" \
  -e GIT_SHA="${GIT_SHA}" \
  -e ANNOTATIONS="${ANNOTATIONS}" \
  -e JMETER_TEST="${JMETER_TEST}" \
  jmetertest perfana-cli run start \
    --config /tests/perfana.yaml \
    --version "${SUT_VERSION}" \
    --annotation "${ANNOTATIONS}"

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "JMeter test completed successfully!"
    echo "=========================================="
else
    echo ""
    echo "=========================================="
    echo "JMeter test failed!"
    echo "=========================================="
  fi

exit $EXIT_CODE
