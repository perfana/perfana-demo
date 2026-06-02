#!/usr/bin/env bash
# ==================================================================================================
# Perfana - stop
# --------------------------------------------------------------------------------------------------
# Stops and removes the containers. Named volumes (database, Keycloak, Grafana,
# Valkey) are PRESERVED so no data is lost.
#
#   ./stop.sh              stop containers, keep data
#   ./stop.sh --volumes    ALSO delete all data volumes (destructive!)
# ==================================================================================================
set -euo pipefail
cd "$(dirname "$0")"

if [[ "${1:-}" == "--volumes" ]]; then
  echo "WARNING: this deletes ALL Perfana data volumes (postgres, keycloak, grafana, valkey)."
  read -r -p "Type 'DELETE' to confirm: " confirm
  [[ "$confirm" == "DELETE" ]] || { echo "Aborted."; exit 1; }
  docker compose down --volumes
else
  docker compose down
fi
