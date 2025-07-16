#!/bin/bash

source common.sh

docker compose down -v

# Cross-platform sed command using shared function
cross_platform_sed 's|<apiKey>[^$][^<]*</apiKey>|<apiKey>__apiKey__</apiKey>|' loadtest/pom.xml
