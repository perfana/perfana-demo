#!/usr/bin/env bash
# Restores postgres_data from a snapshot tgz. Wipes existing volume first.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

SNAP="${1:?usage: $0 <snapshot.tgz>}"
[ -f "$SNAP" ] || { log_error "snapshot not found: $SNAP"; exit 1; }

log_step "Stopping stack to free the volume"
docker compose -f "$LAB_DIR/lab/docker-compose.stack.yml" down

log_step "Wiping perfana-lab_postgres_data volume"
docker volume rm perfana-lab_postgres_data 2>/dev/null || true
docker volume create perfana-lab_postgres_data

log_step "Restoring snapshot $SNAP"
docker run --rm \
  -v perfana-lab_postgres_data:/target \
  -v "$(dirname "$SNAP")":/backup:ro \
  alpine:3.19 \
  sh -c "cd /target && tar xzf /backup/$(basename "$SNAP")"

log_step "Bringing stack back up (postgres + pgbouncer + redis + keycloak first)"
docker compose -f "$LAB_DIR/lab/docker-compose.stack.yml" up -d postgres pgbouncer redis keycloak
wait_for_postgres 120

log_step "Starting api + worker"
docker compose -f "$LAB_DIR/lab/docker-compose.stack.yml" up -d perfana-api perfana-worker perfana-web
wait_for_api 180

log_step "Waiting for CAGGs to catch up"
TARGET_END="$(psql_run_quiet -c "SELECT max(time) FROM requests_raw;")"
log_info "Latest data timestamp: $TARGET_END — waiting for CAGGs to refresh past this"
for i in $(seq 1 30); do
  CAUGHT_UP=$(psql_run_quiet -c "
    SELECT bool_and(
      coalesce(last_successful_finish, '1970-01-01'::timestamptz) > '$TARGET_END'::timestamptz - interval '1 minute'
    )
    FROM timescaledb_information.job_stats js
    JOIN timescaledb_information.jobs j ON j.job_id = js.job_id
    WHERE j.proc_name = 'policy_refresh_continuous_aggregate';" 2>/dev/null || echo "f")
  if [ "$CAUGHT_UP" = "t" ]; then
    log_info "CAGGs caught up after $((i*30))s"
    break
  fi
  log_info "  CAGG catch-up wait... ($((i*30))s)"
  sleep 30
done

log_info "restore-db done"
