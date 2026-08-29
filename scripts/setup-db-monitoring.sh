#!/usr/bin/env bash
# Installs (or refreshes) the database self-monitoring in the Perfana database.
#
# Creates the "monitoring" schema, its hypertable and two TimescaleDB background jobs
# that sample pg_stat_* into it. Nothing Perfana owns is touched. Idempotent: re-run it
# after an upgrade, or to pick up changes to monitoring/pg-monitoring.sql.
#
# The Grafana instance in this stack reads the result through the datasource it already
# has, so no exporter and no Prometheus are involved. Dashboard: "PostgreSQL health".
set -euo pipefail

cd "$(dirname "$0")/.."

if ! docker compose ps postgres --status running --quiet | grep -q .; then
  echo "postgres is not running — start the stack first (./start.sh)" >&2
  exit 1
fi

PSQL=(docker compose exec -T postgres
      psql -U "${POSTGRES_USER:-perfana}" -d "${POSTGRES_DB:-perfana}" -v ON_ERROR_STOP=1)

# Worker budget. TimescaleDB background workers and parallel query workers both come out
# of max_worker_processes, which defaults to 8 -- under timescaledb.max_background_workers
# (16) plus max_parallel_workers (8). Refresh policies then lose the race for a worker and
# log "failed to start job", leaving continuous aggregates behind with nothing but a
# background log line to say so. The samplers this script installs are jobs too, so they
# would suffer the same fate.
#
# docker-compose.yml passes this on the command line, which covers a fresh deployment. An
# existing container keeps the Cmd it was created with, and `docker compose restart` will
# not change that -- so set it in postgresql.auto.conf as well, where it lives in pgdata
# and survives any restart method or image upgrade.
NEEDED=32
CURRENT=$("${PSQL[@]}" -tAc "SHOW max_worker_processes" | tr -d '[:space:]')

if [ "${CURRENT:-0}" -lt "$NEEDED" ]; then
  echo "max_worker_processes is $CURRENT, raising it to $NEEDED ..."
  "${PSQL[@]}" -c "ALTER SYSTEM SET max_worker_processes = $NEEDED" > /dev/null
  echo
  echo "  !! max_worker_processes only takes effect after a PostgreSQL restart:"
  echo "         docker compose up -d postgres"
  echo "     Until then, background jobs may still fail to start a worker."
  echo
else
  echo "max_worker_processes is $CURRENT — enough for the background workers."
fi

echo "Applying monitoring/pg-monitoring.sql ..."
docker compose exec -T postgres \
  psql -U "${POSTGRES_USER:-perfana}" -d "${POSTGRES_DB:-perfana}" -v ON_ERROR_STOP=1 \
  < monitoring/pg-monitoring.sql > /dev/null

echo
docker compose exec -T postgres \
  psql -U "${POSTGRES_USER:-perfana}" -d "${POSTGRES_DB:-perfana}" -c "
    SELECT proc_name AS sampler, schedule_interval, next_start
    FROM timescaledb_information.jobs
    WHERE proc_schema = 'monitoring'
    ORDER BY proc_name;"

echo "Done. Give it a minute, then open the 'PostgreSQL health' dashboard in Grafana."
