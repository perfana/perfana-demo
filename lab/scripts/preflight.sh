#!/usr/bin/env bash
# Validates Docker Desktop sizing, operator inputs, dependencies before stage runs.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

ERRORS=0

log_step "Checking docker info for memory allocation"
TOTAL_MEM_GB=$(docker info --format '{{.MemTotal}}' | awk '{printf "%.0f\n", $1/1024/1024/1024}')
if (( TOTAL_MEM_GB < 24 )); then
  log_warn "Docker Desktop has only ${TOTAL_MEM_GB} GB; spec requires >=24 GB (16 stack + 5 drivers + overhead)."
  log_warn "Settings -> Resources -> Memory in Docker Desktop. Lab may run but with paging."
  ERRORS=$((ERRORS+1))
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

log_step "Checking perfana-jmeter-timescaledb in mavenLocal"
MVN_DIR="$HOME/.m2/repository/io/perfana/perfana-jmeter-timescaledb"
if [ ! -d "$MVN_DIR" ] || [ -z "$(ls -A "$MVN_DIR" 2>/dev/null)" ]; then
  log_error "MISSING: $MVN_DIR/<version>"
  log_error "  Run: cd ~/workspace/perfana-jmeter-timescaledb && ./gradlew publishToMavenLocal"
  ERRORS=$((ERRORS+1))
fi

log_step "Checking driver image"
docker image inspect perfana/lab-driver:0.1.0 >/dev/null 2>&1 || {
  log_error "MISSING: perfana/lab-driver:0.1.0 image"
  log_error "  Run: cd lab/driver && ./gradlew shadowJar && docker build -t perfana/lab-driver:0.1.0 -f docker/Dockerfile ."
  ERRORS=$((ERRORS+1))
}

log_step "Checking python deps for report rendering"
python3 -c "import matplotlib, pandas" 2>/dev/null || {
  log_warn "matplotlib/pandas not installed; install via: pip install -r lab/reports/requirements.txt"
  ERRORS=$((ERRORS+1))
}

if (( ERRORS > 0 )); then
  log_error "Preflight failed with $ERRORS issue(s). Fix the above and re-run."
  exit 1
fi
log_info "Preflight OK"
