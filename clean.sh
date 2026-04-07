#!/bin/bash
# Stops all services and removes volumes (all data will be lost)
docker compose down -v

# Reset API keys in pom files back to placeholder
for pom in ./loadtest/pom.xml ./jmeter/pom.xml; do
  if [ -f "$pom" ]; then
    sed -i.bak "s|<apiKey>[^<]*</apiKey>|<apiKey>PERFANA_API_KEY_PLACEHOLDER</apiKey>|g" "$pom" && rm -f "$pom.bak"
    echo "Reset API key in $pom"
  fi
done
