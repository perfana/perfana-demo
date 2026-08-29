#!/usr/bin/env bash
# Wrapper for redis-sampler.py: waits for the monitoring schema, then keeps one psql
# open and feeds it the sampler's INSERTs. If either side dies the container exits and
# Docker restarts it, which is the whole supervision this needs.
set -euo pipefail
# pipefail matters here: psql is the right-hand side of the pipe, and its death must
# fail the script rather than be masked by python's exit status.

until psql -qtAc 'SELECT 1 FROM monitoring.pg_samples LIMIT 0' >/dev/null 2>&1; do
  echo "waiting for monitoring.pg_samples — run scripts/setup-db-monitoring.sh" >&2
  sleep 15
done

echo "sampling ${REDIS_HOST:-redis}:${REDIS_PORT:-6379} every ${SAMPLE_INTERVAL:-10}s" >&2
python3 "$(dirname "$0")/redis-sampler.py" | psql -q -v ON_ERROR_STOP=1
