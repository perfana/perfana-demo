#!/bin/bash

source common.sh

echo "Starting Mongo cluster ..."
docker-compose --compatibility up -d --remove-orphans mongo{1,2,3}

echo "Configuring Mongo replica-set ..."
sleep 1
$DOCKER_CMD run -ti --rm -v $CONFIG_FILE:/init-mongo.js --net perfana-blog_perfana mongo:4.4-rc /usr/bin/mongo --host mongo1 --port 27011 /init-mongo.js

echo "Bringing up databases that need a little bit more time to start up..."
docker-compose --compatibility up -d mariadb
docker-compose --compatibility up -d influxdb

echo "Starting Grafana ..."
docker-compose --compatibility up -d grafana

echo "Sleeping for 10 secs to give containers some time to start up..."
sleep 10

existingApiKeys=$(curl -X GET -H "Content-Type: application/json" http://perfana:perfana@localhost:3000/api/auth/keys 2>/dev/null)
if [[ $existingApiKeys == [] ]] ; then
    echo "Creating Grafana API key..."
    apiKey=$(curl -v -X POST -H "Content-Type: application/json" -d '{"name":"Perfana","role":"Admin"}' http://perfana:perfana@localhost:3000/api/auth/keys 2>/dev/null | cut -d '"' -f 8)
    echo "Replacing apiKey in docker-compose file with: ${apiKey}" 
    sed -i "s/\"apiKey\": \".*\"/\"apiKey\": \"$apiKey\"/g" docker-compose.yml
fi    

echo "Starting Perfana ..."
docker-compose --compatibility up -d perfana
echo "Sleeping for 10 secs to give Perfana a chance to start up..."
sleep 10

if [[ $existingApiKeys == [] ]] ; then
    echo "Creating fixture data ..."
    docker-compose --compatibility up -d perfana-fixture
fi


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
docker-compose --compatibility up -d optimus-prime-fe
docker-compose --compatibility up -d optimus-prime-be
docker-compose --compatibility up -d jenkins


echo "Done!"

