#!/usr/bin/env bash
# Re-runs analyze-test on each test_run that has NULL pct_agg_passed in
# test_run_transaction_stats — populates the success-filtered sketch added
# in 0.2.47.85 (#298). Filters to a SUT prefix when given.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
source "$LAB_DIR/lab/.api-key.env"

API_URL="${API_URL:-http://localhost:13001/api}"
PER_RUN_TIMEOUT_S="${PER_RUN_TIMEOUT_S:-600}"
SUT_PREFIX="${1:-}"

mapfile -t RUNS < <(docker exec perfana-lab-postgres psql -U perfana -d perfana -At -c "
  SELECT DISTINCT test_run_id
  FROM test_run_transaction_stats
  WHERE pct_agg_passed IS NULL
    ${SUT_PREFIX:+AND test_run_id LIKE '${SUT_PREFIX}%'}
  ORDER BY test_run_id;")

[ "${#RUNS[@]}" -eq 0 ] && { log_info "no runs with NULL pct_agg_passed${SUT_PREFIX:+ matching ${SUT_PREFIX}*}"; exit 0; }
log_info "backfill targets: ${#RUNS[@]} test_runs"

for trid in "${RUNS[@]}"; do
  log_step "[$trid] enqueueing analyze-test"
  RESP=$(curl -sf -X POST "$API_URL/data/analyzeTest/$trid" \
    -H "Authorization: Bearer $PERFANA_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"force": true}') || { log_error "[$trid] enqueue failed"; exit 1; }
  JOB_ID=$(echo "$RESP" | jq -r '.jobId // .id // .data.jobId // .data.id // empty')
  log_info "[$trid] job=$JOB_ID polling DB"

  T0=$(date +%s)
  while true; do
    NULLS=$(docker exec perfana-lab-postgres psql -U perfana -d perfana -At -c "
      SELECT COUNT(*) FROM test_run_transaction_stats
      WHERE test_run_id = '$trid' AND pct_agg_passed IS NULL;")
    [ "$NULLS" -eq 0 ] && break
    [ $(( $(date +%s) - T0 )) -ge "$PER_RUN_TIMEOUT_S" ] && { log_error "[$trid] timed out after ${PER_RUN_TIMEOUT_S}s with $NULLS NULL rows"; exit 2; }
    if ! docker ps --format '{{.Names}} {{.Status}}' | grep -q '^perfana-lab-worker .*Up'; then
      log_info "[$trid] worker down — waiting up to 60s for restart"
      for _ in $(seq 1 12); do
        sleep 5
        docker ps --format '{{.Names}} {{.Status}}' | grep -q '^perfana-lab-worker .*Up' && break
      done
    fi
    sleep 5
  done
  ELAPSED=$(( $(date +%s) - T0 ))
  log_info "[$trid] pct_agg_passed populated in ${ELAPSED}s"

  sleep 60
done
log_info "backfill complete"
