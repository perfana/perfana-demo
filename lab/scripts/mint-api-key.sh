#!/usr/bin/env bash
# Mints a perfana API key via Keycloak admin token + perfana-api /api-keys endpoint.
# Writes the bearer token to lab/.api-key.env so other scripts can source it.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:18080}"
REALM="${KEYCLOAK_REALM:-perfana-prod}"
ADMIN_USER="${KEYCLOAK_ADMIN_USER:-admin@perfana.io}"
ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-Admin123!}"
API_URL="${API_URL:-http://localhost:13001/api}"
KEYCLOAK_CLIENT_SECRET="${KEYCLOAK_CLIENT_SECRET:-perfana-api-secret-change-in-production}"

log_step "Getting Keycloak token for $ADMIN_USER"
TOKEN=$(curl -sf -X POST "$KEYCLOAK_URL/realms/$REALM/protocol/openid-connect/token" \
  -d "grant_type=password" \
  -d "client_id=perfana-api" \
  -d "client_secret=$KEYCLOAK_CLIENT_SECRET" \
  -d "username=$ADMIN_USER" \
  -d "password=$ADMIN_PASSWORD" \
  -d "scope=openid" | jq -r '.access_token')
[ -n "$TOKEN" ] && [ "$TOKEN" != "null" ] || { log_error "Token request failed"; exit 1; }

log_step "Minting API key for label 'lab-soak'"
RESP=$(curl -sf -X POST "$API_URL/api-keys" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"description":"lab-soak","ttl":"7d","roles":["perfana-admin"]}')

KEY=$(echo "$RESP" | jq -r '.token')
ID=$(echo "$RESP" | jq -r '.apiKey.id')
[ -n "$KEY" ] && [ "$KEY" != "null" ] || { log_error "API-key mint failed: $RESP"; exit 1; }

cat > "$LAB_DIR/lab/.api-key.env" <<EOK
PERFANA_API_KEY=$KEY
PERFANA_API_KEY_ID=$ID
EOK
chmod 600 "$LAB_DIR/lab/.api-key.env"

log_info "API key minted (id=$ID), saved to lab/.api-key.env"
