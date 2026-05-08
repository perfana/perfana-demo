#!/usr/bin/env bash
# Validates Docker Desktop sizing, operator inputs, dependencies before stage runs.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

ERRORS=0
WARNINGS=0

log_step "Checking docker info for memory allocation"
TOTAL_MEM_GB=$(docker info --format '{{.MemTotal}}' | awk '{printf "%.0f\n", $1/1024/1024/1024}')
if (( TOTAL_MEM_GB < 24 )); then
  log_warn "Docker Desktop has only ${TOTAL_MEM_GB} GB; spec recommends >=24 GB (16 stack + 5 drivers + overhead)."
  log_warn "Settings -> Resources -> Memory in Docker Desktop. Lab may run but with paging."
  WARNINGS=$((WARNINGS+1))
fi

log_step "Checking required files"
[ -f "$LAB_DIR/lab/driver/url-patterns.txt" ] || {
  log_error "MISSING: lab/driver/url-patterns.txt - copy from .example and customise"
  ERRORS=$((ERRORS+1))
}
[ -f "$LAB_DIR/lab/.env" ] || {
  log_error "MISSING: lab/.env - copy from lab/.env.example"
  ERRORS=$((ERRORS+1))
}

log_step "Checking driver image"
if ! docker image inspect perfana/lab-driver:0.1.0 >/dev/null 2>&1; then
  log_error "MISSING: perfana/lab-driver:0.1.0 image"
  log_error "  Run: cd lab/driver && ./gradlew shadowJar && docker build -t perfana/lab-driver:0.1.0 -f docker/Dockerfile ."
  ERRORS=$((ERRORS+1))

  # Driver gradle build needs perfana-jmeter-timescaledb in mavenLocal.
  MVN_DIR="$HOME/.m2/repository/io/perfana/perfana-jmeter-timescaledb"
  if [ ! -d "$MVN_DIR" ] || [ -z "$(ls -A "$MVN_DIR" 2>/dev/null)" ]; then
    log_error "MISSING: $MVN_DIR/<version> (required to build the driver image)"
    log_error "  Run: cd ~/workspace/perfana-jmeter-timescaledb && ./gradlew publishToMavenLocal"
    ERRORS=$((ERRORS+1))
  fi
fi

log_step "Checking python deps for report rendering"
python3 -c "import matplotlib, pandas" 2>/dev/null || {
  log_warn "matplotlib/pandas not installed (only needed for report rendering)"
  log_warn "  install via: pip install -r lab/reports/requirements.txt"
  WARNINGS=$((WARNINGS+1))
}

if (( ERRORS > 0 )); then
  log_error "Preflight failed with $ERRORS error(s). Fix the above and re-run."
  exit 1
fi
if (( WARNINGS > 0 )); then
  log_warn "Preflight passed with $WARNINGS warning(s) — see above."
fi
log_info "Preflight OK"
