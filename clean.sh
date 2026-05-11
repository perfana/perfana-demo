#!/bin/bash
# Stops all services and removes volumes (all data will be lost)
docker compose down -v

# Reset API keys back to placeholder
if [ -f ./loadtest/pom.xml ]; then
  sed -i.bak "s|<apiKey>[^<]*</apiKey>|<apiKey>PERFANA_API_KEY_PLACEHOLDER</apiKey>|g" ./loadtest/pom.xml && rm -f ./loadtest/pom.xml.bak
  echo "Reset API key in loadtest/pom.xml"
fi

if [ -f ./jmeter/perfana.yaml ]; then
  sed -i.bak 's|apiKey:.*|apiKey: "PERFANA_API_KEY_PLACEHOLDER"|' ./jmeter/perfana.yaml && rm -f ./jmeter/perfana.yaml.bak
  echo "Reset API key in jmeter/perfana.yaml"
fi
