#!/usr/bin/env bash
# Asserts the 4 SUTs hash to 4 distinct space partitions (chunks) on requests_raw.
# Run after the first chunk per SUT has been created (~90s into Stage 1).
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

EXPECTED=4
log_step "Querying chunk distribution per SUT for requests_raw"

ROW_COUNT=$(psql_run_quiet -c "SELECT count(*) FROM requests_raw WHERE system_under_test LIKE 'lab-sut-%';" 2>/dev/null || echo 0)
log_info "Sample rows for lab SUTs: $ROW_COUNT"
if (( ROW_COUNT < 100 )); then
  log_warn "Too few rows yet ($ROW_COUNT) — wait longer before running this check."
  exit 0
fi

DISTINCT_CHUNKS=$(psql_run_quiet -c "
  WITH sut_chunks AS (
    SELECT DISTINCT
      tableoid::regclass::text AS chunk,
      system_under_test
    FROM requests_raw
    WHERE system_under_test LIKE 'lab-sut-%'
  )
  SELECT count(DISTINCT chunk) FROM sut_chunks;
")

log_info "Distinct chunks containing lab SUTs: $DISTINCT_CHUNKS (expected: $EXPECTED)"

psql_run -c "
  SELECT system_under_test, tableoid::regclass::text AS chunk, count(*) AS rows
  FROM requests_raw
  WHERE system_under_test LIKE 'lab-sut-%'
  GROUP BY 1, 2
  ORDER BY 1, 2;
"

if (( DISTINCT_CHUNKS < EXPECTED )); then
  log_error "Two or more SUTs collide in the same hash partition."
  log_error "Rename a SUT in docker-compose.drivers.yml (e.g. lab-sut-a -> lab-sut-aa) and rerun."
  exit 2
fi
log_info "Chunk distribution OK"
