#!/usr/bin/env bash
# Shared helpers for lab scripts. Source from any script:
#   source "$(dirname "$0")/lib/common.sh"
set -euo pipefail

LAB_DIR="${LAB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
REPORTS_DIR="$LAB_DIR/lab/reports"

log_info()  { printf '\033[0;32m[INFO]\033[0m  %s\n' "$*"; }
log_warn()  { printf '\033[0;33m[WARN]\033[0m  %s\n' "$*"; }
log_error() { printf '\033[0;31m[ERROR]\033[0m %s\n' "$*"; }
log_step()  { printf '\033[0;34m[STEP]\033[0m  %s\n' "$*"; }

# psql via docker exec on the lab postgres
psql_run() {
  docker exec -i perfana-lab-postgres psql -U perfana -d perfana "$@"
}

psql_run_quiet() {
  docker exec -i perfana-lab-postgres psql -U perfana -d perfana -tAq "$@"
}

# pgbouncer admin (SHOW POOLS, SHOW STATS, etc.)
bouncer_admin() {
  PGPASSWORD="${POSTGRES_PASSWORD:-perfana}" docker exec -i perfana-lab-pgbouncer \
    psql -h localhost -p 6432 -U perfana -d pgbouncer -tAq -c "$1"
}

# Wait until pg_isready returns 0
wait_for_postgres() {
  local timeout="${1:-90}"
  local i=0
  until docker exec perfana-lab-postgres pg_isready -U perfana -d perfana >/dev/null 2>&1; do
    if (( i >= timeout )); then
      log_error "postgres did not become ready in ${timeout}s"
      return 1
    fi
    sleep 1
    ((i++))
  done
  log_info "postgres ready in ${i}s"
}

# Wait until perfana-api /health returns 200
wait_for_api() {
  local timeout="${1:-180}"
  local i=0
  until curl -sf -o /dev/null http://localhost:13001/api/health; do
    if (( i >= timeout )); then
      log_error "api did not become healthy in ${timeout}s"
      return 1
    fi
    sleep 2
    i=$((i+2))
  done
  log_info "api healthy in ${i}s"
}

# Resolve a per-run reports directory and create it
make_run_dir() {
  local stage="$1"
  local ts="${RUN_TS:-$(date -u +%Y%m%dT%H%M%SZ)}"
  local dir="$REPORTS_DIR/$ts/$stage"
  mkdir -p "$dir/timeseries"
  echo "$dir"
}
