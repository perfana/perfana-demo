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

SLEEP_TIME=${SLEEP_TIME:-15}
echo "using sleep time of $SLEEP_TIME seconds, use -s or --sleep option to change"

echo "Starting Mongo cluster ..."
docker-compose --compatibility up -d --remove-orphans mongo{1,2,3}

echo "Configuring Mongo replica-set ..."
sleep 1
$DOCKER_CMD run --rm -v $CONFIG_FILE:/init-mongo.js --net $PERFANA_NETWORK mongo:$MONGO_VERSION /usr/bin/mongo --host mongo1 --port 27011 /init-mongo.js

echo "Bringing up databases that need a little bit more time to start up..."
docker-compose --compatibility up -d mariadb
docker-compose --compatibility up -d influxdb

echo "Sleeping for $SLEEP_TIME secs to give the db containers some time to start up..."
sleep $SLEEP_TIME

echo "Starting Grafana ..."
docker-compose --compatibility up -d grafana

echo "Sleeping for $SLEEP_TIME secs to give Grafana some time to start up..."
sleep $SLEEP_TIME

API_KEY_EXISTS=false

perfanaKey=`curl -X GET -H "Content-Type: application/json" "http://$GRAFANA_CREDS@localhost:3000/api/auth/keys" 2>/dev/null`
echo "perfanaKey: $perfanaKey"
if [[ $perfanaKey == *"Perfana"* ]]; then
  API_KEY_EXISTS=true
fi

echo "Starting Perfana ..."
docker-compose --compatibility up -d perfana
echo "Sleeping for $SLEEP_TIME secs to give Perfana a chance to start up..."
sleep $SLEEP_TIME

echo "Starting the rest of the environment ..."
docker-compose --compatibility up -d perfana-grafana
docker-compose --compatibility up -d perfana-snapshot
docker-compose --compatibility up -d perfana-check
docker-compose --compatibility up -d perfana-scheduler
docker-compose --compatibility up -d telegraf
docker-compose --compatibility up -d wiremock
#docker-compose --compatibility up -d omnidb
docker-compose --compatibility up -d prometheus
docker-compose --compatibility up -d alertmanager
docker-compose --compatibility up -d jaeger
echo "Sleeping for $SLEEP_TIME secs to give containers a chance to start up..."
sleep $SLEEP_TIME
docker-compose --compatibility up -d optimus-prime-fe
docker-compose --compatibility up -d optimus-prime-be
#echo "Sleeping for $SLEEP_TIME secs to give afterburners a chance to start up..."
#sleep $SLEEP_TIME
docker-compose --compatibility up -d jenkins

#echo "Sleeping for $SLEEP_TIME secs to give jenkins a chance to start up..."
#sleep $SLEEP_TIME

# if no apiKey was found, assume it is a fresh install and load fixture data
if [[  $API_KEY_EXISTS == false ]]; then

    echo "Creating fixture data ..."
    docker-compose --compatibility up -d perfana-fixture
else
    echo "Existing api keys found in Grafana, skipping fixture data ..."
fi

#docker-compose --compatibility up -d rabbitmq

echo "Done!"
