#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset

source common.sh

# check if jq is installed
if ! command -v jq &> /dev/null
then
    echo "WARNING: jq command could not be found, the key inject action in first clean run will fail, please install"
fi

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
docker-compose --compatibility up -d elasticsearch
docker-compose --compatibility up -d logstash
docker-compose --compatibility up -d kibana


echo "Sleeping for $SLEEP_TIME secs to give the db containers some time to start up..."
sleep $SLEEP_TIME

echo "Starting Grafana ..."
docker-compose --compatibility up -d grafana

echo "Sleeping for $SLEEP_TIME secs to give Grafana some time to start up..."
sleep $SLEEP_TIME 

existingPerfanaUserId=$(curl -X GET -H "Content-Type: application/json"  http://$GRAFANA_CREDS@localhost:3000/api/auth/keys 2>/dev/null | jq '.[] | select(.name == "Perfana")' | jq .id)

if [ -z "$existingPerfanaUserId" ];  then
    echo "Creating Grafana API key..."
    apiKey=$(curl -X POST -H "Content-Type: application/json" -d '{"name":"Perfana","role":"Admin"}' http://$GRAFANA_CREDS@localhost:3000/api/auth/keys 2>/dev/null | jq -r '.key')
    if [[ -z "$apiKey" ]] || [[ "$apiKey" == "null" ]]; then
        echo "Issue creating Grafana API key, no API key returned from create call: abort!"
        exit 123
    fi
    echo "Replacing apiKey in docker-compose file with: ${apiKey}"
    if [ "$(check-os)" == "mac" ]; then
        sed -i '' "s/\"apiKey\": \".*\"/\"apiKey\": \"$apiKey\"/g" docker-compose.yml
    else
        sed -i "s/\"apiKey\": \".*\"/\"apiKey\": \"$apiKey\"/g" docker-compose.yml
    fi
else
    echo "Grafana API key is already present, no need to create a new one."
fi

echo "Starting Perfana ..."
docker-compose --compatibility up -d perfana
echo "Sleeping for $SLEEP_TIME secs to give Perfana a chance to start up..."
sleep $SLEEP_TIME


echo "Starting the rest of the environment ..."

docker-compose --compatibility up -d perfana-grafana
docker-compose --compatibility up -d perfana-snapshot
docker-compose --compatibility up -d perfana-check
docker-compose --compatibility up -d telegraf
docker-compose --compatibility up -d wiremock
docker-compose --compatibility up -d omnidb
docker-compose --compatibility up -d prometheus
docker-compose --compatibility up -d alertmanager
docker-compose --compatibility up -d jaeger
echo "Sleeping for $SLEEP_TIME secs to give containers a chance to start up..."
sleep $SLEEP_TIME
docker-compose --compatibility up -d optimus-prime-fe
docker-compose --compatibility up -d optimus-prime-be
echo "Sleeping for $SLEEP_TIME secs to give afterburners a chance to start up..."
sleep $SLEEP_TIME
docker-compose --compatibility up -d jenkins

echo "Sleeping for $SLEEP_TIME secs to give jenkins a chance to start up..."
sleep $SLEEP_TIME


# if no apiKey was found, assume it is a fresh install and load fixture data
if [ -z "$existingPerfanaUserId" ];  then
    echo "No api keys found Grafana, creating fixture data ..."
    docker-compose --compatibility up -d perfana-fixture
else
    echo "Existing api keys found in Grafana, skipping fixture data ..."
fi

echo "Create index pattern in Kibana"

curl -X POST -u elastic:perfana -H "Content-Type: application/json" -H "kbn-xsrf:true"  "http://localhost:5601/api/saved_objects/index-pattern/springboot-logs-pattern" -d '{ "attributes": { "title":"spring-boot-app-logs*", "timeFieldName":"@timestamp"}}'  -w "\n" | jq


echo "Done!"

