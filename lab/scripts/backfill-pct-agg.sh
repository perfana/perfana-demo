#!/usr/bin/env bash
# Re-runs analyze-test on each test_run that has NULL pct_agg in
# ds_metric_statistics, polling the DB directly until the rows are populated.
# Avoids the API /jobs/:id/status endpoint, which proved unreliable (returns
# active even when the worker has finished and the redis ProgressReporter has
# closed). One run at a time, 10-min per-run cap, fail fast on worker death.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
source "$LAB_DIR/lab/.api-key.env"

API_URL="${API_URL:-http://localhost:13001/api}"
PER_RUN_TIMEOUT_S="${PER_RUN_TIMEOUT_S:-600}"

mapfile -t RUNS < <(docker exec perfana-lab-postgres psql -U perfana -d perfana -At -c "
  SELECT DISTINCT test_run_id
  FROM ds_metric_statistics
  WHERE pct_agg IS NULL
  ORDER BY test_run_id;")

[ "${#RUNS[@]}" -eq 0 ] && { log_info "no test_runs with NULL pct_agg — nothing to do"; exit 0; }
log_info "backfill targets: ${#RUNS[@]} test_runs"

for trid in "${RUNS[@]}"; do
  log_step "[$trid] enqueueing analyze-test"
  RESP=$(curl -sf -X POST "$API_URL/data/analyzeTest/$trid" \
    -H "Authorization: Bearer $PERFANA_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"force": true}') || { log_error "[$trid] enqueue failed"; exit 1; }
  JOB_ID=$(echo "$RESP" | jq -r '.jobId // .id // .data.jobId // .data.id // empty')
  log_info "[$trid] job=$JOB_ID — polling DB for pct_agg fill"

  T0=$(date +%s)
  while true; do
    NULLS=$(docker exec perfana-lab-postgres psql -U perfana -d perfana -At -c "
      SELECT COUNT(*) FROM ds_metric_statistics
      WHERE test_run_id = '$trid' AND pct_agg IS NULL;")
    [ "$NULLS" -eq 0 ] && break
    ELAPSED=$(( $(date +%s) - T0 ))
    if [ "$ELAPSED" -ge "$PER_RUN_TIMEOUT_S" ]; then
      log_error "[$trid] still $NULLS NULL pct_agg rows after ${PER_RUN_TIMEOUT_S}s — giving up"
      exit 2
    fi
    if ! docker ps --format '{{.Names}} {{.Status}}' | grep -q '^perfana-lab-worker .*Up'; then
      log_info "[$trid] worker container down — waiting for compose restart policy to bring it back"
      for _ in $(seq 1 12); do
        sleep 5
        docker ps --format '{{.Names}} {{.Status}}' | grep -q '^perfana-lab-worker .*Up' && break
      done
      if ! docker ps --format '{{.Names}} {{.Status}}' | grep -q '^perfana-lab-worker .*Up'; then
        log_error "[$trid] worker did not come back after 60s — aborting"
        exit 3
      fi
      log_info "[$trid] worker restarted; re-enqueueing"
      RESP=$(curl -sf -X POST "$API_URL/data/analyzeTest/$trid" \
        -H "Authorization: Bearer $PERFANA_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{"force": true}') || { log_error "[$trid] re-enqueue failed"; exit 1; }
      JOB_ID=$(echo "$RESP" | jq -r '.jobId // .id // .data.jobId // .data.id // empty')
      log_info "[$trid] re-enqueued job=$JOB_ID"
      T0=$(date +%s)
    fi
    sleep 5
  done

  ELAPSED=$(( $(date +%s) - T0 ))
  log_info "[$trid] pct_agg populated in ${ELAPSED}s"

  # Give the JobLockService lock for this scope time to expire before the
  # next analyze. Without this, a Redis-keepalive crash at finalization
  # leaks the lock (perfana#294) and the next job immediately gets blocked.
  sleep 60
done

log_info "backfill complete — all 16 control runs have pct_agg populated"
