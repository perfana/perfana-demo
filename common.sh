#!/usr/bin/env bash

DOCKER_HOST_IP=$(docker network inspect perfana-demo_perfana -f '{{range .IPAM.Config}}{{.Gateway}}{{end}}')
DOCKER_CMD="docker"
CONFIG_FILE=$(pwd)/init-mongo.js

# https://stackoverflow.com/questions/3466166/how-to-check-if-running-in-cygwin-mac-or-linux
if [ "$(uname)" != "Darwin" ] && [ "$(expr substr $(uname -s) 1 6)" == "CYGWIN" ]; then
    CONFIG_FILE=`cygpath.exe -m $(pwd)/init-mongo.js`
    DOCKER_CMD="winpty docker"
fi

export CONFIG_FILE DOCKER_CMD DOCKER_HOST_IP
