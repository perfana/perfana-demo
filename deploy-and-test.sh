#!/usr/bin/env bash

if [ $# -ne 1 ]; then
  echo "Supply one option: 'baseline', 'cpu' or 'pool'."
  exit 1
fi

while (( "$#" )); do
  case "$1" in
    baseline)
      echo "Deploying and testing baseline."
      export SUT_VERSION=2.4.3-good-baseline
      export GIT_SHA=c3ee4b9
      export ANNOTATIONS="Proxy Dev: make cpu more efficient"
      docker-compose stop afterburner-fe
      docker-compose stop afterburner-be
      docker-compose rm -f afterburner-fe
      docker-compose rm -f  afterburner-be
      docker-compose up -d afterburner-fe
      docker-compose up -d afterburner-be
      break
    ;;
    cpu)
      echo "Deploying and testing baseline with cpu issue."
      export SUT_VERSION=2.4.3-changed-matrix-calc
      export GIT_SHA=decc58d
      docker-compose up -d --force-recreate  afterburner-fe
      docker-compose up -d --force-recreate  afterburner-be
      break
    ;;
    pool)
      echo "Deploying and testing version with connection pool issue."
      export SUT_VERSION=2.4.3-default-http-conn-pool
      export GIT_SHA=e17d3dd
      docker-compose up -d --force-recreate  afterburner-fe
      docker-compose up -d --force-recreate  afterburner-be
      break
    ;;
    *)
      echo "Error: Unsupported parameter '$1'" >&2
      echo "Valid options are: 'baseline', 'cpu' and 'pool'."
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
        if docker-compose ps "$service" | grep -q "Up"; then
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
docker-compose down loadtest
docker-compose up -d loadtest
echo "Running load test with SUT_VERSION=${SUT_VERSION} and GIT_SHA=${GIT_SHA}"
docker-compose exec loadtest mvn clean -DSUT_VERSION=${SUT_VERSION} -DGIT_SHA=${GIT_SHA} -Dannotations="${ANNOTATIONS}" events-gatling:test
