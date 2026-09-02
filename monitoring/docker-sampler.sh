#!/usr/bin/env bash
# Wrapper for docker-sampler.py: waits for the monitoring schema, then keeps one psql
# open and feeds it the sampler's INSERTs. Mirrors redis-sampler.sh — if either side
# dies the container exits and Docker restarts it.
set -euo pipefail

until psql -qtAc 'SELECT 1 FROM monitoring.pg_samples LIMIT 0' >/dev/null 2>&1; do
  echo "waiting for monitoring.pg_samples — run scripts/setup-db-monitoring.sh" >&2
  sleep 15
done

echo "sampling ${DOCKER_API:-http://docker-socket-proxy:2375} every ${SAMPLE_INTERVAL:-15}s" >&2
python3 "$(dirname "$0")/docker-sampler.py" | psql -q -v ON_ERROR_STOP=1
