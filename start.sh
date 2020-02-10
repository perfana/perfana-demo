#!/bin/bash

PAUSE=15

CONFIG_FILE=$(pwd)/init-mongo.js
DOCKER_CMD="docker"

# https://stackoverflow.com/questions/3466166/how-to-check-if-running-in-cygwin-mac-or-linux
if [ "$(expr substr $(uname -s) 1 6)" == "CYGWIN" ]; then    
    CONFIG_FILE=`cygpath.exe -m $(pwd)/init-mongo.js`
    DOCKER_CMD="winpty docker"
fi

#export DOCKER_HOST_IP=$(ifconfig | grep -A1 docker| grep -E "([0-9]{1,3}\.){3}[0-9]{1,3}" | grep -v 127.0.0.1 | awk '{ print $2 }' | cut -f2 -d: | head -n1)
# Platform independent way...
export DOCKER_HOST_IP=$(docker network inspect bridge -f '{{range .IPAM.Config}}{{.Gateway}}{{end}}')

echo "Starting Mongo cluster..."
docker-compose up -d mongo{1,2,3}

echo "Configuring Mongo replica-set..."
sleep 1
$DOCKER_CMD run -ti --rm -v $CONFIG_FILE:/init-mongo.js --net perfana-demo_perfana mongo:4.2-bionic /usr/bin/mongo --host mongo1 /init-mongo.js

echo "Sleeping for ${PAUSE} secs to give Mongo a chance to start the replicaset..."
sleep ${PAUSE}

echo "Bringing up the rest of the Perfana test environment..."
docker-compose up -d

echo "Done!"

