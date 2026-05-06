#!/usr/bin/env bash
# Snapshots the postgres_data volume to lab/snapshots/post-stage1-<ts>.tgz
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

OUT="${1:-$LAB_DIR/lab/snapshots/post-stage1-$(date -u +%Y%m%dT%H%M%SZ).tgz}"
log_step "Snapshotting postgres_data volume -> $OUT"

mkdir -p "$(dirname "$OUT")"

# Stop perfana-api/worker so volume is in a quiescent state — postgres can stay running
docker compose -f "$LAB_DIR/lab/docker-compose.stack.yml" stop perfana-api perfana-worker || true

# Use a temporary helper container to tar the volume
docker run --rm \
  -v perfana-lab_postgres_data:/source:ro \
  -v "$(dirname "$OUT")":/backup \
  alpine:3.19 \
  tar czf "/backup/$(basename "$OUT")" -C /source .

log_info "Snapshot done: $(du -h "$OUT" | cut -f1)"

# Restart api/worker
docker compose -f "$LAB_DIR/lab/docker-compose.stack.yml" start perfana-api perfana-worker
