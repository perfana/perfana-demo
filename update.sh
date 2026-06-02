#!/usr/bin/env bash
# ==================================================================================================
# Perfana - update
# --------------------------------------------------------------------------------------------------
# Upgrades to the image versions pinned in docker-compose.yml:
#   1. Pull updated images
#   2. Re-run database migrations
#   3. Recreate changed services
#
# Pin image tags by editing docker-compose.yml before running this. Back up the
# database first (see INSTALL.md "Backups").
# ==================================================================================================
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  echo "ERROR: .env not found." >&2
  exit 1
fi

echo "[1/3] Pulling images..."
docker compose pull

echo "[2/3] Running database migrations..."
docker compose up -d postgres valkey
if ! docker compose run --rm perfana-migration; then
  echo "WARNING: migration runner exited non-zero. Check: docker compose logs perfana-migration" >&2
fi

echo "[3/3] Recreating services..."
docker compose up -d

echo "Done. Verify: docker compose ps"
