#!/bin/bash

CONFIG_FILE=`$(pwd)/init-mongo.js`
DOCKER_CMD="docker"

# https://stackoverflow.com/questions/3466166/how-to-check-if-running-in-cygwin-mac-or-linux
if [ "$(expr substr $(uname -s) 1 6)" == "Cygwin" ]; then
    CONFIG_FILE=`cygpath.exe -m $(pwd)/init-mongo.js`
    DOCKER_CMD="winpty docker"
fi

$DOCKER_CMD run -ti --rm --net perfana-demo_perfana -v $CONFIG_FILE:/init-mongo.js mongo:4.0-xenial /usr/bin/mongo --host mongo1 init-mongo.js
