#!/bin/bash

source common.sh

docker-compose down -v

sed -i '' 's|<apiKey>[^<]*</apiKey>|<apiKey>__apiKey__</apiKey>|' loadtest/pom.xml