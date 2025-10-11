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
docker compose  up -d perfana-grafana
docker compose  up -d perfana-snapshot
docker compose  up -d perfana-ds-api
docker compose  up -d perfana-ds-worker
docker compose  up -d perfana-ds-metric-worker
#docker compose  up -d perfana-mcp
#docker compose  up -d perfana-chat
docker compose  up -d telegraf
docker compose  up -d prometheus
docker compose  up -d alertmanager
docker compose  up -d tempo
docker compose  up -d pyroscope
docker compose  up -d loki

echo "Sleeping for $SLEEP_TIME secs to give containers a chance to start up..."
sleep $SLEEP_TIME
docker-compose  up -d afterburner-fe
docker-compose  up -d afterburner-be
echo "Sleeping for $SLEEP_TIME secs to give afterburners a chance to start up..."
sleep $SLEEP_TIME
docker-compose  up -d loadtest
echo "Done!"
