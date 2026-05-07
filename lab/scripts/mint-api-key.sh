#!/usr/bin/env bash
# Mints a perfana API key via Keycloak password grant + perfana-api /api-keys endpoint.
# Mirrors the proven recipe in init-demo.sh: post-import provisioning via kcadm.sh
# (reset password, enable directAccessGrantsEnabled on perfana-web, disable OTP in
# direct-grant flow), then password grant against the public perfana-web client.
# Writes the bearer token to lab/.api-key.env so other scripts can source it.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

KC_CONTAINER="${KC_CONTAINER:-perfana-lab-keycloak}"
KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:18080}"
REALM="${KEYCLOAK_REALM:-perfana-prod}"
KC_ADMIN="${KEYCLOAK_ADMIN:-admin}"
KC_ADMIN_PW="${KEYCLOAK_ADMIN_PASSWORD:-admin}"
PERFANA_USER="${PERFANA_USER:-admin@perfana.io}"
PERFANA_PASSWORD="${PERFANA_PASSWORD:-Test@1234}"
API_URL="${API_URL:-http://localhost:13001/api}"

kcadm() {
  docker exec "$KC_CONTAINER" /opt/keycloak/bin/kcadm.sh "$@"
}

log_step "Configuring kcadm credentials"
kcadm config credentials --server http://localhost:8080 --realm master \
  --user "$KC_ADMIN" --password "$KC_ADMIN_PW" >/dev/null

log_step "Resetting password for $PERFANA_USER"
USER_ID=$(kcadm get users -r "$REALM" -q "username=$PERFANA_USER" --fields id 2>/dev/null | jq -r '.[0].id')
[ -n "$USER_ID" ] && [ "$USER_ID" != "null" ] || { log_error "User $PERFANA_USER not found in realm $REALM"; exit 1; }
kcadm set-password -r "$REALM" --userid "$USER_ID" --new-password "$PERFANA_PASSWORD" >/dev/null

log_step "Configuring perfana-web client (direct grants + lab port 14000)"
WEB_CLIENT_UUID=$(kcadm get clients -r "$REALM" --fields id,clientId 2>/dev/null \
  | jq -r '.[] | select(.clientId=="perfana-web") | .id')
[ -n "$WEB_CLIENT_UUID" ] && [ "$WEB_CLIENT_UUID" != "null" ] || { log_error "perfana-web client not found"; exit 1; }
kcadm update "clients/$WEB_CLIENT_UUID" -r "$REALM" \
  -s directAccessGrantsEnabled=true \
  -s 'redirectUris=["http://localhost:3000/*","http://localhost:4000/*","http://localhost:4001/*","http://localhost:4002/*","http://localhost:14000/*","https://app.perfana.io/*","https://*.perfana.dev/*"]' \
  -s 'webOrigins=["http://localhost:3000","http://localhost:4000","http://localhost:4001","http://localhost:4002","http://localhost:14000","https://app.perfana.io"]' >/dev/null

log_step "Disabling OTP in direct-grant flow"
kcadm get "authentication/flows/direct%20grant/executions" -r "$REALM" 2>/dev/null \
  | jq -r '.[] | select(.providerId=="direct-grant-validate-otp") | .id' \
  | while read -r OTP_ID; do
      [ -n "$OTP_ID" ] || continue
      kcadm update "authentication/flows/direct%20grant/executions" -r "$REALM" \
        -b "{\"id\":\"$OTP_ID\",\"requirement\":\"DISABLED\",\"providerId\":\"direct-grant-validate-otp\"}" >/dev/null
    done

log_step "Getting password-grant token via perfana-web (public client)"
KC_RESP=$(curl -s -X POST "$KEYCLOAK_URL/realms/$REALM/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=password' \
  -d 'client_id=perfana-web' \
  --data-urlencode "username=$PERFANA_USER" \
  --data-urlencode "password=$PERFANA_PASSWORD")
TOKEN=$(echo "$KC_RESP" | jq -r '.access_token')
[ -n "$TOKEN" ] && [ "$TOKEN" != "null" ] || { log_error "Token request failed: $KC_RESP"; exit 1; }

log_step "Ensuring Demo organization exists and user is a member"
ORG_ID=$(curl -s -X POST "$API_URL/organizations" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"Demo","description":"Lab soak organization"}' | jq -r '.id // empty')
if [ -z "$ORG_ID" ]; then
  ORG_ID=$(curl -sf "$API_URL/organizations" -H "Authorization: Bearer $TOKEN" \
    | jq -r '.[] | select(.name=="Demo") | .id')
fi
[ -n "$ORG_ID" ] && [ "$ORG_ID" != "null" ] || { log_error "Could not create or find Demo organization"; exit 1; }

IS_MEMBER=$(curl -sf "$API_URL/organizations/$ORG_ID/members" -H "Authorization: Bearer $TOKEN" \
  | jq -r --arg uid "$USER_ID" '[.[] | select(.user_id==$uid)] | length')
if [ "$IS_MEMBER" = "0" ] || [ -z "$IS_MEMBER" ]; then
  curl -sf -X POST "$API_URL/organizations/$ORG_ID/members" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "{\"userId\":\"$USER_ID\",\"roles\":[\"org-admin\"]}" >/dev/null
fi

log_step "Refreshing token so org membership is in claims"
KC_RESP=$(curl -s -X POST "$KEYCLOAK_URL/realms/$REALM/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=password' -d 'client_id=perfana-web' \
  --data-urlencode "username=$PERFANA_USER" \
  --data-urlencode "password=$PERFANA_PASSWORD")
TOKEN=$(echo "$KC_RESP" | jq -r '.access_token')
[ -n "$TOKEN" ] && [ "$TOKEN" != "null" ] || { log_error "Token refresh failed: $KC_RESP"; exit 1; }

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
