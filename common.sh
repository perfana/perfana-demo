#!/usr/bin/env bash

MONGO_VERSION="4.4"

COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-$(basename $(pwd))}

# use current directory as basename for the network, this only works when common.sh is in same dir as 
# the docker-compose.yml file and is executed from that directory
PERFANA_NETWORK=${COMPOSE_PROJECT_NAME}_perfana
if [[ "$(docker network ls)" =~ $PERFANA_NETWORK ]]; then
   DOCKER_HOST_IP=$(docker network inspect $PERFANA_NETWORK -f '{{range .IPAM.Config}}{{.Gateway}}{{end}}')
else 
   echo "WARN: network '$PERFANA_NETWORK' does not exist"
   DOCKER_HOST_IP=""
fi

# https://stackoverflow.com/questions/3466166/how-to-check-if-running-in-cygwin-mac-or-linux#answer-33828925
# use as: current_os="$(check-os)"
check-os () { 
    case "$OSTYPE" in
      linux*)   echo "linux" ;;
      darwin*)  echo "mac" ;; 
      win*)     echo "windows" ;;
      msys*)    echo "git-bash" ;;
      cygwin*)  echo "cygwin" ;;
      *)        echo "unknown" ;;
    esac
}

current_os="$(check-os)"
if [ $current_os != "mac" ] && [ $current_os == "cygwin" ]; then
    CONFIG_FILE=`cygpath.exe -m $(pwd)/init-mongo.js`
    DOCKER_CMD="winpty docker"
else
    DOCKER_CMD="docker"
    CONFIG_FILE=$(pwd)/init-mongo.js
fi

GRAFANA_CREDS=perfana:perfana

confirm() {
    # call with a prompt string or use a default
    read -r -p "${1:-Are you sure? [y/N]} " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            true
            ;;
        *)
            false
            ;;
    esac
}

# make sure there is a copy of docker-compose.yml, for start.sh,stop.sh,clean.sh
if [ -f docker-compose.yml ]; then
   echo "create copy of docker-compose.yml"
   cp docker-compose-template.yml docker-compose.yml
fi

