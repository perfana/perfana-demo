#!/usr/bin/env bash
# Creates 4 test_runs (one per SUT) via API and writes IDs to test-run-ids.env
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
source "$LAB_DIR/lab/.api-key.env"

API_URL="${API_URL:-http://localhost:13001/api}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"

declare -A SUTS=( [a]=lab-sut-a [b]=lab-sut-b [c]=lab-sut-c [d]=lab-sut-d )

OUT="$LAB_DIR/lab/test-run-ids.env"
: > "$OUT"

for k in a b c d; do
  SUT="${SUTS[$k]}"
  TRID="${SUT}-${TS}"
  log_step "Creating test_run $TRID"
  RESP=$(curl -sf -X POST "$API_URL/test" \
    -H "Authorization: Bearer $PERFANA_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"testRunId\": \"$TRID\",
      \"systemUnderTest\": \"$SUT\",
      \"testEnvironment\": \"lab\",
      \"workload\": \"lab-soak\",
      \"start\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",
      \"completed\": false
    }") || { log_error "create failed for $SUT"; exit 1; }
  echo "TEST_RUN_ID_SUT_$(echo "$k" | tr a-z A-Z)=$TRID" >> "$OUT"
done

log_info "Wrote 4 test-run-ids to $OUT"
cat "$OUT"
