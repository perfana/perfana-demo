#!/usr/bin/env bash
# Triggers POST /api/data/analyzeTest/:testRunId, polls /jobs/:id/status until done.
# Records timing to refetch-timing.csv (appends).
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

OUT_DIR="${1:?usage: $0 <out-dir> <test-run-id>}"
TRID="${2:?missing test-run-id}"

source "$LAB_DIR/lab/.api-key.env"
API_URL="${API_URL:-http://localhost:13001/api}"
CSV="$OUT_DIR/refetch-timing.csv"
[ -f "$CSV" ] || echo "test_run_id,enqueued_at,job_id,started_at,finished_at,total_ms,status" > "$CSV"

ENQ_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ENQ_NS=$(date +%s%N)

log_step "Enqueueing analyzeTest for $TRID"
RESP=$(curl -sf -X POST "$API_URL/data/analyzeTest/$TRID" \
  -H "Authorization: Bearer $PERFANA_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"force": true}') || { log_error "enqueue failed for $TRID"; exit 1; }

JOB_ID=$(echo "$RESP" | jq -r '.jobId // .id // .data.jobId // .data.id // empty')
[ -n "$JOB_ID" ] || { log_error "no jobId in response: $RESP"; exit 1; }
log_info "Enqueued job $JOB_ID for $TRID"

log_step "Polling /data/jobs/$JOB_ID/status"
STATUS=""
START_TS=""
while [ "$STATUS" != "completed" ] && [ "$STATUS" != "failed" ]; do
  sleep 5
  STATUS_RESP=$(curl -sf "$API_URL/data/jobs/$JOB_ID/status" \
    -H "Authorization: Bearer $PERFANA_API_KEY" 2>/dev/null || echo '{}')
  STATUS=$(echo "$STATUS_RESP" | jq -r '.status // .data.status // "unknown"')
  if [ -z "$START_TS" ]; then
    START_TS=$(echo "$STATUS_RESP" | jq -r '.startedAt // .data.startedAt // empty')
  fi
  log_info "  job $JOB_ID status=$STATUS"
  if [ $(( ($(date +%s%N) - ENQ_NS) / 1000000000 )) -gt 1800 ]; then
    log_error "refetch timed out after 30 min"
    STATUS="timeout"
    break
  fi
done

END_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
END_NS=$(date +%s%N)
TOTAL_MS=$(( (END_NS - ENQ_NS) / 1000000 ))

echo "$TRID,$ENQ_TS,$JOB_ID,$START_TS,$END_TS,$TOTAL_MS,$STATUS" >> "$CSV"
log_info "refetch $TRID -> $STATUS in ${TOTAL_MS}ms"

[ "$STATUS" = "completed" ] || exit 2
