#!/usr/bin/env bash
# Polls Performance Analysis card endpoints every 30s for each test run.
# Records latency to perf-analysis-latency.csv.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

OUT_DIR="${1:?usage: $0 <out-dir> [duration-seconds]}"
DURATION_SECONDS="${2:-900}"  # default 15 min

source "$LAB_DIR/lab/.api-key.env"
source "$LAB_DIR/lab/test-run-ids.env"

API_URL="${API_URL:-http://localhost:13001/api}"
CSV="$OUT_DIR/perf-analysis-latency.csv"
echo "timestamp,test_run_id,endpoint,http_status,latency_ms,response_bytes" > "$CSV"

ENDPOINTS=(
  "/test-runs/{TRID}"
  "/test-runs/{TRID}/transactions"
  "/test-runs/{TRID}/throughput"
  "/test-runs/{TRID}/virtual-users"
  "/test-runs/{TRID}/errors"
)

TEST_RUN_IDS=(
  "$TEST_RUN_ID_SUT_A" "$TEST_RUN_ID_SUT_B"
  "$TEST_RUN_ID_SUT_C" "$TEST_RUN_ID_SUT_D"
)

END=$(( $(date +%s) + DURATION_SECONDS ))
log_info "Polling perf-analysis for ${DURATION_SECONDS}s, 30s interval"

trap 'log_info "poll-perf-analysis stopping"; exit 0' TERM INT

while [ "$(date +%s)" -lt "$END" ]; do
  for trid in "${TEST_RUN_IDS[@]}"; do
    for tmpl in "${ENDPOINTS[@]}"; do
      path=${tmpl//\{TRID\}/$trid}
      url="${API_URL}${path}"
      START_NS=$(date +%s%N)
      RESP=$(curl -s -o /dev/null -w '%{http_code}|%{size_download}' \
        -H "Authorization: Bearer $PERFANA_API_KEY" \
        --max-time 30 "$url" || echo "000|0")
      END_NS=$(date +%s%N)
      LATENCY_MS=$(( (END_NS - START_NS) / 1000000 ))
      STATUS="${RESP%|*}"
      BYTES="${RESP#*|}"
      echo "$(date -u +%Y-%m-%dT%H:%M:%SZ),$trid,$path,$STATUS,$LATENCY_MS,$BYTES" >> "$CSV"
    done
  done
  sleep 30
done

log_info "poll-perf-analysis done; wrote $(wc -l < "$CSV") lines"
