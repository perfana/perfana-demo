#!/usr/bin/env bash

if [ $# -ne 1 ]; then
  echo "Supply one option:"
  echo "  JMeter Webshop (parallel): 'baseline', 'cpu', 'backend', 'pool'"
  echo "  JMeter single test: 'webshop-browse', 'webshop-checkout', 'webshop-all'"
  exit 1
fi

# Function to restart afterburner services
restart_afterburner() {
    docker-compose -f docker-compose-next-gen.yml stop afterburner-fe
    docker-compose -f docker-compose-next-gen.yml stop afterburner-be
    docker-compose -f docker-compose-next-gen.yml rm -f afterburner-fe
    docker-compose -f docker-compose-next-gen.yml rm -f afterburner-be
    docker-compose -f docker-compose-next-gen.yml up -d afterburner-fe
    docker-compose -f docker-compose-next-gen.yml up -d afterburner-be
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
    webshop-browse)
      echo "Deploying and running JMeter Webshop Browse & Search test only."
      export SUT_VERSION=2.4.3-good-baseline
      export GIT_SHA=4e2db5f
      export ANNOTATIONS="JMeter Webshop Browse & Search Simulation"
      export JMETER_TEST=webshop-browse-search
      restart_afterburner
      break
    ;;
    webshop-checkout)
      echo "Deploying and running JMeter Webshop Checkout Flow test only."
      export SUT_VERSION=2.4.3-good-baseline
      export GIT_SHA=4e2db5f
      export ANNOTATIONS="JMeter Webshop Checkout Flow Simulation"
      export JMETER_TEST=webshop-checkout-flow
      restart_afterburner
      break
    ;;
    webshop-all)
      echo "Deploying and running ALL JMeter Webshop tests in parallel (Browse + Checkout)."
      export SUT_VERSION=2.4.3-good-baseline
      export GIT_SHA=4e2db5f
      export ANNOTATIONS="JMeter Webshop Combined Simulation (Parallel)"
      export JMETER_TEST="webshop-*.jmx"
      restart_afterburner
      break
    ;;
    *)
      echo "Error: Unsupported parameter '$1'" >&2
      echo "Valid options:"
      echo "  JMeter Webshop (parallel): 'baseline', 'cpu', 'backend', 'pool'"
      echo "  JMeter single test: 'webshop-browse', 'webshop-checkout', 'webshop-all'"
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
        if docker-compose -f docker-compose-next-gen.yml ps "$service" | grep -q "Up"; then
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

# Ensure Perfana API is accessible before running tests
#echo "Waiting for Perfana API to be ready..."
#if ! wait_for_service "perfana-api"; then
#    echo "Perfana API service failed to become healthy"
#    exit 1
#fi

# Wait for Perfana Web to be ready
#echo "Waiting for Perfana Web to be ready..."
#if ! wait_for_service "perfana-web"; then
#    echo "Perfana Web service failed to become healthy"
#    exit 1
#fi

# Check if Perfana API is responding
echo "Checking Perfana API health..."
max_api_attempts=15
api_attempt=1
while [ $api_attempt -le $max_api_attempts ]; do
    if curl -f http://localhost:3001/api/auth/health > /dev/null 2>&1; then
        echo "Perfana API is responding!"
        break
    fi
    echo "API attempt $api_attempt/$max_api_attempts: Perfana API not responding yet..."
    sleep 4
    api_attempt=$((api_attempt + 1))
done

if [ $api_attempt -gt $max_api_attempts ]; then
    echo "Timeout waiting for Perfana API to respond"
    exit 1
fi

# Run either JMeter or Gatling test based on JMETER_TEST variable
if [ -n "$JMETER_TEST" ]; then
    echo "Running JMeter test: ${JMETER_TEST} with SUT_VERSION=${SUT_VERSION}"

    # Build jmetertest container if needed
    docker-compose -f docker-compose-next-gen.yml build jmetertest
    docker-compose -f docker-compose-next-gen.yml up -d jmetertest

    # Determine test file pattern (add .jmx if not already a pattern)
    if [[ "$JMETER_TEST" == *".jmx"* ]] || [[ "$JMETER_TEST" == *"*"* ]]; then
        TEST_FILE_PATTERN="${JMETER_TEST}"
    else
        TEST_FILE_PATTERN="${JMETER_TEST}.jmx"
    fi

    # Build Maven arguments (annotations quoted to handle spaces/colons)
    MVN_ARGS="-DSUT_VERSION=${SUT_VERSION} -DGIT_SHA=${GIT_SHA} -DtestFile=${TEST_FILE_PATTERN}"

    # Run JMeter test via Maven (testRunId is generated by Perfana init call)
    # Parallel execution is enabled by default in pom.xml (runTestsInParallel=true)
    docker-compose -f docker-compose-next-gen.yml exec jmetertest mvn clean verify ${MVN_ARGS} "-Dannotations=${ANNOTATIONS}"
else
    docker-compose -f docker-compose-next-gen.yml down loadtest
    docker-compose -f docker-compose-next-gen.yml up -d loadtest
    echo "Running Gatling load test with SUT_VERSION=${SUT_VERSION} and GIT_SHA=${GIT_SHA}"
    docker-compose -f docker-compose-next-gen.yml exec loadtest mvn clean -U -DSUT_VERSION=${SUT_VERSION} -DGIT_SHA=${GIT_SHA} -Dannotations="${ANNOTATIONS}" events-gatling:test
fi
