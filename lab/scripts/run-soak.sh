#!/usr/bin/env bash
# Orchestrates one stage of the lab.
#
# Usage:
#   run-soak.sh --stage 1
#   run-soak.sh --stage 2 --use-snapshot lab/snapshots/post-stage1-XXX.tgz
#   run-soak.sh --stage 3
#   run-soak.sh --stage all
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

STAGE=""
SNAPSHOT=""
KEEP_DB=""
while [ $# -gt 0 ]; do
  case "$1" in
    --stage) STAGE="$2"; shift 2;;
    --use-snapshot) SNAPSHOT="$2"; shift 2;;
    --keep-db) KEEP_DB=1; shift;;
    *) log_error "unknown arg: $1"; exit 1;;
  esac
done
[ -n "$STAGE" ] || { log_error "missing --stage"; exit 1; }

export RUN_TS="${RUN_TS:-$(date -u +%Y%m%dT%H%M%SZ)}"
log_info "Run timestamp: $RUN_TS"

cd "$LAB_DIR"
set -a
source ./lab/.env
set +a

capture_driver_logs() {
  local STAGE_DIR="$1"
  local CSV="$STAGE_DIR/driver_metrics.csv"
  echo "timestamp,driver,sut,scenario,rps_target,rps_actual,hikari_active,hikari_idle,hikari_waiting,buffer_total,buffer_request_raw,buffer_transactions,buffer_errors,buffer_vusers,buffer_url_patterns,under_pressure" > "$CSV"
  for i in $(seq 1 12); do
    docker logs "perfana-lab-driver-$i" 2>&1 \
      | grep '^METRICS,' \
      | sed 's/^METRICS,//' \
      >> "$CSV" || true
  done
}

end_of_stage_snapshots() {
  local STAGE_DIR="$1"
  log_step "Capturing pg_stat_statements + chunk distribution"
  psql_run_quiet -c "
    SELECT 'queryid,calls,total_exec_time,mean_exec_time,query'
    UNION ALL
    SELECT queryid::text || ',' || calls || ',' || total_exec_time || ',' || mean_exec_time
      || ',\"' || replace(left(query, 200), '\"', '\"\"') || '\"'
    FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 30;" \
    > "$STAGE_DIR/pg_stat_statements_top.csv" 2>/dev/null || true
  psql_run_quiet -c "
    SELECT 'hypertable,total_chunks,compressed_chunks'
    UNION ALL
    SELECT hypertable_name || ',' || count(*) || ','
      || coalesce(count(*) FILTER (WHERE is_compressed)::text, '0')
    FROM timescaledb_information.chunks
    WHERE hypertable_name IN ('requests_raw','requests_error','transactions')
    GROUP BY 1;" \
    > "$STAGE_DIR/chunk_distribution.csv" 2>/dev/null || true
}

run_stage_1() {
  local STAGE_DIR; STAGE_DIR="$(make_run_dir stage1-ingest)"
  log_step "STAGE 1: ingestion only — $STAGE_DIR"

  log_step "Preflight"
  ./lab/scripts/preflight.sh

  log_step "Generating pgbouncer userlist"
  ./lab/scripts/mint-pgbouncer-userlist.sh perfana "${POSTGRES_PASSWORD:-perfana}" lab/pgbouncer/userlist.txt

  if [ -z "$KEEP_DB" ]; then
    log_step "Bringing up stack"
    docker compose -f lab/docker-compose.stack.yml --env-file lab/.env down -v
    docker compose -f lab/docker-compose.stack.yml --env-file lab/.env up -d
    wait_for_postgres 120
  else
    log_step "Reusing existing stack (--keep-db)"
  fi
  wait_for_api 180

  if [ -n "$KEEP_DB" ] && [ -f lab/.api-key.env ]; then
    log_step "Reusing existing API key (--keep-db)"
  else
    log_step "Minting API key"
    ./lab/scripts/mint-api-key.sh
  fi

  log_step "Starting observability"
  ./lab/scripts/observability.sh "$STAGE_DIR" &
  OBS_PID=$!

  log_step "Starting per-SUT Perfana test runs (perfana-cli)"
  set -a; source lab/.api-key.env; set +a
  DRIVER_TEST_RUN_ID=_ docker compose -f lab/docker-compose.drivers.yml rm -fs 2>/dev/null || true
  mkdir -p "$STAGE_DIR/perfana-cli"
  local CLI_PIDS=()
  for sut in a b m d; do
    perfana-cli run start --config "lab/perfana/sut-$sut.yaml" \
      > "$STAGE_DIR/perfana-cli/sut-$sut.log" 2>&1 &
    CLI_PIDS+=($!)
  done

  log_step "Warmup, then verifying chunk distribution"
  sleep 90
  ./lab/scripts/verify-chunk-distribution.sh || {
    log_error "Chunk distribution check failed — aborting Stage 1"
    for pid in "${CLI_PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
    DRIVER_TEST_RUN_ID=_ docker compose -f lab/docker-compose.drivers.yml down
    kill "$OBS_PID" 2>/dev/null || true
    exit 2
  }

  log_step "Soak running, waiting for perfana-cli runs to finish..."
  for pid in "${CLI_PIDS[@]}"; do wait "$pid" || true; done

  log_step "perfana-cli runs done, capturing logs + end-of-stage snapshots"
  capture_driver_logs "$STAGE_DIR"
  end_of_stage_snapshots "$STAGE_DIR"

  log_step "Stopping observability"
  kill "$OBS_PID" 2>/dev/null || true
  wait "$OBS_PID" 2>/dev/null || true

  log_step "Removing driver containers"
  DRIVER_TEST_RUN_ID=_ docker compose -f lab/docker-compose.drivers.yml down

  if [ -z "$KEEP_DB" ]; then
    log_step "Snapshotting DB"
    ./lab/scripts/snapshot-db.sh "$LAB_DIR/lab/snapshots/post-stage1-${RUN_TS}.tgz"
  else
    log_step "Skipping DB snapshot (--keep-db)"
  fi

  log_step "Generating report"
  python3 lab/reports/generate-report.py --stage 1 --dir "$STAGE_DIR"

  log_info "Stage 1 done. Snapshot: lab/snapshots/post-stage1-${RUN_TS}.tgz"
  log_info "Report: $STAGE_DIR/report.md"
}

run_stage_2() {
  local STAGE_DIR; STAGE_DIR="$(make_run_dir stage2-query)"
  log_step "STAGE 2: query only — $STAGE_DIR"

  if [ -z "$SNAPSHOT" ]; then
    SNAPSHOT="$(ls -t lab/snapshots/post-stage1-*.tgz 2>/dev/null | head -1 || true)"
    [ -n "$SNAPSHOT" ] || { log_error "no Stage 1 snapshot found; pass --use-snapshot"; exit 1; }
  fi
  log_info "Restoring from $SNAPSHOT"
  ./lab/scripts/restore-db.sh "$SNAPSHOT"

  log_step "Re-minting API key after restart"
  ./lab/scripts/mint-api-key.sh
  set -a; source lab/.api-key.env; source lab/test-run-ids.env; set +a

  log_step "Starting observability"
  ./lab/scripts/observability.sh "$STAGE_DIR" &
  OBS_PID=$!

  log_step "Polling Performance Analysis card for 15 min"
  ./lab/scripts/poll-perf-analysis.sh "$STAGE_DIR" 900

  log_step "Triggering force re-fetch on $TEST_RUN_ID_SUT_A"
  ./lab/scripts/trigger-refetch.sh "$STAGE_DIR" "$TEST_RUN_ID_SUT_A" || true

  log_step "Stopping observability"
  kill "$OBS_PID" 2>/dev/null || true
  wait "$OBS_PID" 2>/dev/null || true

  log_step "Generating report"
  python3 lab/reports/generate-report.py --stage 2 --dir "$STAGE_DIR"

  log_info "Stage 2 done. Report: $STAGE_DIR/report.md"
}

run_stage_3() {
  local STAGE_DIR; STAGE_DIR="$(make_run_dir stage3-concurrent)"
  log_step "STAGE 3: concurrent — $STAGE_DIR"

  log_step "Preflight"
  ./lab/scripts/preflight.sh

  log_step "Generating pgbouncer userlist"
  ./lab/scripts/mint-pgbouncer-userlist.sh perfana "${POSTGRES_PASSWORD:-perfana}" lab/pgbouncer/userlist.txt

  log_step "Bringing up fresh stack"
  docker compose -f lab/docker-compose.stack.yml --env-file lab/.env down -v
  docker compose -f lab/docker-compose.stack.yml --env-file lab/.env up -d
  wait_for_postgres 120
  wait_for_api 180

  log_step "Minting API key + seeding test runs"
  ./lab/scripts/mint-api-key.sh
  ./lab/scripts/seed-test-runs.sh

  log_step "Starting observability"
  ./lab/scripts/observability.sh "$STAGE_DIR" &
  OBS_PID=$!

  log_step "Starting drivers"
  set -a; source lab/.api-key.env; source lab/test-run-ids.env; set +a
  docker compose -f lab/docker-compose.drivers.yml --env-file lab/.env up -d

  log_step "Warmup, then verifying chunks"
  sleep 90
  ./lab/scripts/verify-chunk-distribution.sh

  log_step "Starting query workload (background, 55 min cap)"
  ./lab/scripts/poll-perf-analysis.sh "$STAGE_DIR" 3300 &
  POLL_PID=$!

  log_step "Schedule force re-fetches at +10min and +30min"
  (
    sleep 600
    ./lab/scripts/trigger-refetch.sh "$STAGE_DIR" "$TEST_RUN_ID_SUT_B" || true
  ) &
  RF1=$!
  (
    sleep 1800
    ./lab/scripts/trigger-refetch.sh "$STAGE_DIR" "$TEST_RUN_ID_SUT_C" || true
  ) &
  RF2=$!

  log_step "Soak running, waiting for drivers..."
  while docker ps --filter "name=perfana-lab-driver-" --filter "status=running" -q | grep -q .; do
    sleep 30
    log_info "  drivers still running ($(docker ps --filter "name=perfana-lab-driver-" --filter "status=running" -q | wc -l | tr -d ' ') active)"
  done

  log_step "Drivers done; tearing down query/refetch workloads"
  kill "$POLL_PID" "$RF1" "$RF2" 2>/dev/null || true
  wait "$POLL_PID" "$RF1" "$RF2" 2>/dev/null || true

  log_step "Capturing driver logs + end-of-stage snapshots"
  capture_driver_logs "$STAGE_DIR"
  end_of_stage_snapshots "$STAGE_DIR"

  log_step "Stopping observability + drivers"
  kill "$OBS_PID" 2>/dev/null || true
  wait "$OBS_PID" 2>/dev/null || true
  docker compose -f lab/docker-compose.drivers.yml down

  log_step "Generating report"
  python3 lab/reports/generate-report.py --stage 3 --dir "$STAGE_DIR"

  log_info "Stage 3 done. Report: $STAGE_DIR/report.md"
}

case "$STAGE" in
  1)   run_stage_1 ;;
  2)   run_stage_2 ;;
  3)   run_stage_3 ;;
  all) run_stage_1; run_stage_2; run_stage_3 ;;
  *)   log_error "unknown stage: $STAGE"; exit 1 ;;
esac

log_info "All done. Reports under lab/reports/$RUN_TS/"
