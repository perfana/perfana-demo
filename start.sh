#!/bin/bash
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


SLEEP_TIME=${SLEEP_TIME:-15}
echo "using sleep time of $SLEEP_TIME seconds, use -s or --sleep option to change"

echo "Starting Mongo cluster ..."
docker-compose  up -d --remove-orphans mongo{1,2,3}

echo "Configuring Mongo replica-set ..."
sleep 1
$DOCKER_CMD run --rm -v $CONFIG_FILE:/init-mongo.js --net $PERFANA_NETWORK mongo:$MONGO_VERSION /usr/bin/mongo --host mongo1 --port 27011 /init-mongo.js

echo "Bringing up databases that need a little bit more time to start up..."
docker-compose  up -d mariadb
docker-compose  up -d influxdb

echo "Sleeping for $SLEEP_TIME secs to give the db containers some time to start up..."
sleep $SLEEP_TIME

echo "Starting Grafana ..."
docker-compose  up -d grafana

echo "Sleeping for $SLEEP_TIME secs to give Grafana some time to start up..."
sleep $SLEEP_TIME

echo "Starting Perfana ..."
docker-compose  up -d perfana-fe
echo "Sleeping for $SLEEP_TIME secs to give Perfana a chance to start up..."
sleep $SLEEP_TIME

echo "Starting the rest of the environment ..."
docker-compose  up -d perfana-grafana
docker-compose  up -d perfana-snapshot
docker-compose  up -d perfana-check
docker-compose  up -d perfana-scheduler
docker-compose  up -d perfana-ds-api
docker-compose  up -d perfana-ds-worker
docker-compose  up -d perfana-ds-metric-worker

docker-compose  up -d telegraf
# docker-compose  up -d wiremock
docker-compose  up -d prometheus
docker-compose  up -d alertmanager
docker-compose  up -d tempo
docker-compose  up -d pyroscope
docker-compose  up -d loki

echo "Sleeping for $SLEEP_TIME secs to give containers a chance to start up..."
sleep $SLEEP_TIME

docker-compose  up -d afterburner-fe
docker-compose  up -d afterburner-be

echo "Sleeping for $SLEEP_TIME secs to give afterburners a chance to start up..."
sleep $SLEEP_TIME

docker-compose  up -d loadtest

echo "Creating indeces and schemas for perfana-ds-api.."

# Create indexes
curl -X 'POST' \
  'http://localhost:8080/manage/createIndexes?panels=true&metrics=true&metricStatistics=true&controlGroups=true&controlGroupStatistics=true&trackedDifferences=true&adaptInput=true&adaptResults=true&adaptConclusion=true&adaptTrackedResults=true' \
  -H 'accept: application/json' \
  -d ''
# Create schemas
curl -X 'POST' \
  'http://localhost:8080/manage/createSchemas?panels=true&metrics=true&metricStatistics=true&controlGroupStatistics=true&trackedDifferences=true&adaptInput=true&adaptResults=true&adaptTrackedResults=true&adaptConclusion=true' \
  -H 'accept: application/json' \
  -d ''

# Fetch the API key
api_key=$( curl --location 'http://localhost:4000/api/key' \
             --header 'Content-Type: application/json' \
             --user 'perfana:perfana' \
             --data '{
                 "validFor": "1y",
                 "description": "demo"
             }' | jq -r '.key.data')

# Replace __apiKey__ in ./loadtest/pom.xml with the fetched API key
sed -i '' "s/__apiKey__/$api_key/" ./loadtest/pom.xml

echo "Running 3 baseline load tests with SUT_VERSION=${SUT_VERSION} and GIT_SHA=${GIT_SHA}"
./deploy-and-test.sh baseline
./deploy-and-test.sh baseline
./deploy-and-test.sh baseline
echo "Done!"
