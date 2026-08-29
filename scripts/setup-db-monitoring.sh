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
