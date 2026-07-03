#!/usr/bin/env bash
# ==================================================================================================
# Perfana - first-run bootstrap
# --------------------------------------------------------------------------------------------------
# Run ONCE after the first successful ./start.sh. Idempotent: safe to re-run.
# It performs the integration steps that cannot be baked into images:
#
#   1. Align Keycloak client secrets with .env
#   2. Point Keycloak client redirect URIs / web origins / CSP at PERFANA_HOST
#   3. Set the Perfana admin user's password and enable password-grant login
#   4. Create the Perfana organization and make the admin an org-admin
#   5. Re-apply provisioning (benchmarks, dashboards) under that organization
#   6. Create a Grafana service-account token and register Grafana in Perfana
#   7. Create a Perfana API key for load-test result submission
#
# All Perfana/Keycloak/Grafana calls go over localhost (server-local), so this
# works regardless of the public hostname or any reverse proxy in front.
#
# Requires: jq, curl (installed in WSL2 - see INSTALL.md).
# ==================================================================================================
set -uo pipefail
cd "$(dirname "$0")"

[[ -f .env ]] || { echo "ERROR: .env not found." >&2; exit 1; }
set -a; . ./.env; set +a

KC_ADMIN="${KEYCLOAK_ADMIN:-admin}"
KC_ADMIN_PW="${KEYCLOAK_ADMIN_PASSWORD:?KEYCLOAK_ADMIN_PASSWORD must be set}"
REALM="perfana-prod"
SCHEME="${PERFANA_SCHEME:-http}"
HOST="${PERFANA_HOST:-localhost}"
WEB_PORT="${PERFANA_WEB_PORT:-4001}"
GRAFANA_PORT="${GRAFANA_PORT:-3100}"
ORG_NAME="${PERFANA_ORG_NAME:-Perfana}"
PERFANA_USER="${PERFANA_ADMIN_USER:-admin@perfana.io}"
PERFANA_PW="${PERFANA_ADMIN_PASSWORD:?PERFANA_ADMIN_PASSWORD must be set}"

# Every call below is server-local. If a corporate proxy is configured (http_proxy/https_proxy),
# curl would otherwise route localhost through it and fail (proxy can't resolve localhost -> 504).
export no_proxy="localhost,127.0.0.1${no_proxy:+,$no_proxy}"
export NO_PROXY="$no_proxy"

KC_LOCAL="http://localhost:8080"
API_LOCAL="http://localhost:3001"
GRAFANA_LOCAL="http://localhost:${GRAFANA_PORT}"
KC_EXEC=(docker exec perfana-keycloak /opt/keycloak/bin/kcadm.sh)

command -v jq >/dev/null || { echo "ERROR: jq is required. Install it (sudo apt-get install -y jq)." >&2; exit 1; }

wait_for() { # url label tries
  local url="$1" label="$2" tries="${3:-60}"
  echo "       Waiting for $label..."
  for i in $(seq 1 "$tries"); do
    if curl -sf "$url" >/dev/null 2>&1; then echo "       $label ready."; return 0; fi
    sleep 2
  done
  echo "       WARNING: $label not ready in time."; return 1
}

client_uuid() { # clientId
  "${KC_EXEC[@]}" get clients -r "$REALM" -q "clientId=$1" --fields id --format csv 2>/dev/null \
    | tr -d '"\r' | head -1
}

echo "==> Configuring Keycloak (realm: $REALM)"
"${KC_EXEC[@]}" config credentials --server "$KC_LOCAL" --realm master \
  --user "$KC_ADMIN" --password "$KC_ADMIN_PW" 2>/dev/null \
  || { echo "ERROR: kcadm login failed. Is Keycloak healthy?" >&2; exit 1; }

# 1. Align client secrets with .env (best effort)
echo "    - Aligning client secrets with .env"
for pair in "perfana-api:${KEYCLOAK_CLIENT_SECRET:-}" \
            "perfana-admin:${KEYCLOAK_ADMIN_CLIENT_SECRET:-}" \
            "grafana:${GRAFANA_OAUTH_CLIENT_SECRET:-}"; do
  cid="${pair%%:*}"; secret="${pair#*:}"
  [[ -z "$secret" ]] && continue
  uuid="$(client_uuid "$cid")"
  if [[ -n "$uuid" ]]; then
    "${KC_EXEC[@]}" update "clients/$uuid" -r "$REALM" -s "secret=$secret" >/dev/null 2>&1 \
      && echo "        $cid secret set" || echo "        WARNING: could not set $cid secret"
  fi
done

# 2. Point redirect URIs / web origins at PERFANA_HOST (keep localhost for admin)
echo "    - Setting redirect URIs / web origins for host '$HOST'"
web_uuid="$(client_uuid perfana-web)"
if [[ -n "$web_uuid" ]]; then
  "${KC_EXEC[@]}" update "clients/$web_uuid" -r "$REALM" \
    -s "redirectUris=[\"$SCHEME://$HOST:$WEB_PORT/*\",\"http://localhost:$WEB_PORT/*\"]" \
    -s "webOrigins=[\"$SCHEME://$HOST:$WEB_PORT\",\"http://localhost:$WEB_PORT\"]" >/dev/null 2>&1 \
    && echo "        perfana-web client updated" || echo "        WARNING: perfana-web update failed"
fi
graf_uuid="$(client_uuid grafana)"
if [[ -n "$graf_uuid" ]]; then
  "${KC_EXEC[@]}" update "clients/$graf_uuid" -r "$REALM" \
    -s "redirectUris=[\"$SCHEME://$HOST:$GRAFANA_PORT/*\",\"http://localhost:$GRAFANA_PORT/*\"]" \
    -s "webOrigins=[\"$SCHEME://$HOST:$GRAFANA_PORT\",\"http://localhost:$GRAFANA_PORT\"]" >/dev/null 2>&1 \
    && echo "        grafana client updated" || echo "        WARNING: grafana update failed"
fi

# Realm CSP: allow framing Grafana + the web app from the public host
csp="frame-src 'self' $SCHEME://$HOST:$GRAFANA_PORT $SCHEME://$HOST:$WEB_PORT; frame-ancestors 'self' $SCHEME://$HOST:$GRAFANA_PORT $SCHEME://$HOST:$WEB_PORT; object-src 'none';"
"${KC_EXEC[@]}" update realms/"$REALM" \
  -s "browserSecurityHeaders.contentSecurityPolicy=$csp" >/dev/null 2>&1 \
  && echo "    - Realm CSP updated" || echo "    - WARNING: could not update realm CSP"

# 3. Set admin password + enable password-grant login on perfana-web
echo "    - Setting password for $PERFANA_USER"
uid="$("${KC_EXEC[@]}" get users -r "$REALM" -q "username=$PERFANA_USER" --fields id --format csv 2>/dev/null | tr -d '"\r' | head -1)"
if [[ -n "$uid" ]]; then
  "${KC_EXEC[@]}" set-password -r "$REALM" --username "$PERFANA_USER" --new-password "$PERFANA_PW" 2>/dev/null \
    && echo "        password set" || echo "        WARNING: could not set password"
else
  echo "        WARNING: user $PERFANA_USER not found in realm"
fi
if [[ -n "$web_uuid" ]]; then
  "${KC_EXEC[@]}" update "clients/$web_uuid" -r "$REALM" -s directAccessGrantsEnabled=true >/dev/null 2>&1 || true
fi
# Disable the OTP step in the direct-grant flow so password-grant works headlessly
"${KC_EXEC[@]}" get "authentication/flows/direct%20grant/executions" -r "$REALM" 2>/dev/null \
  | jq -r '.[] | select(.displayName | test("OTP";"i")) | .id' 2>/dev/null \
  | while read -r exid; do
      [[ -n "$exid" ]] && "${KC_EXEC[@]}" update "authentication/flows/direct%20grant/executions" -r "$REALM" \
        -b "{\"id\":\"$exid\",\"requirement\":\"DISABLED\"}" >/dev/null 2>&1 || true
    done

echo "==> Waiting for services"
wait_for "$API_LOCAL/api/health" "Perfana API" 60
wait_for "$GRAFANA_LOCAL/api/health" "Grafana" 30

get_token() {
  curl -sf "$KC_LOCAL/realms/$REALM/protocol/openid-connect/token" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -d 'grant_type=password' -d 'client_id=perfana-web' \
    --data-urlencode "username=$PERFANA_USER" \
    --data-urlencode "password=$PERFANA_PW" 2>/dev/null | jq -r '.access_token // empty'
}

echo "==> Configuring Perfana"
TOKEN="$(get_token)"
if [[ -z "$TOKEN" ]]; then
  echo "ERROR: could not obtain a token from Keycloak. Aborting Perfana setup." >&2
  echo "       Check that $PERFANA_USER / password are correct and the realm imported." >&2
  exit 1
fi

# 4. Organization + membership
echo "    - Creating organization '$ORG_NAME'"
ORG_ID="$(curl -sf -X POST "$API_LOCAL/api/organizations" -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"$ORG_NAME\",\"description\":\"$ORG_NAME\"}" | jq -r '.id // empty')"
if [[ -z "$ORG_ID" ]]; then
  ORG_ID="$(curl -sf "$API_LOCAL/api/organizations" -H "Authorization: Bearer $TOKEN" \
    | jq -r ".[] | select(.name==\"$ORG_NAME\") | .id" 2>/dev/null | head -1)"
fi
[[ -n "$ORG_ID" ]] && echo "        org id: $ORG_ID" || echo "        WARNING: could not create/find organization"

if [[ -n "$ORG_ID" ]]; then
  sub="$(echo "$TOKEN" | cut -d. -f2 | tr '_-' '/+' | { read -r p; pad=$(( (4 - ${#p} % 4) % 4 )); printf '%s%*s' "$p" "$pad" '' | tr ' ' '='; } | base64 -d 2>/dev/null | jq -r '.sub // empty')"
  if [[ -n "$sub" ]]; then
    member="$(curl -sf "$API_LOCAL/api/organizations/$ORG_ID/members" -H "Authorization: Bearer $TOKEN" \
      | jq -r "[.[] | select(.user_id==\"$sub\")] | length" 2>/dev/null)"
    if [[ "${member:-0}" == "0" ]]; then
      curl -sf -X POST "$API_LOCAL/api/organizations/$ORG_ID/members" -H "Authorization: Bearer $TOKEN" \
        -H 'Content-Type: application/json' -d "{\"userId\":\"$sub\",\"roles\":[\"org-admin\"]}" >/dev/null 2>&1 \
        && echo "        $PERFANA_USER added as org-admin" || echo "        WARNING: could not add member"
    fi
  fi

  # 5. Re-apply provisioning YAMLs under the real org id
  echo "    - Applying provisioning under org $ORG_ID"
  for f in perfana/provisioning/profiles.yaml perfana/provisioning/profile_benchmarks.yaml \
           perfana/provisioning/profile_grafana_dashboards.yaml perfana/provisioning/template_ds_compare_configs.yaml; do
    [[ -f "$f" ]] && sed -i.bak "s|^organizationId:.*|organizationId: ${ORG_ID}|" "$f" && rm -f "$f.bak"
  done
  docker exec perfana-postgres psql -U perfana -d perfana -v ON_ERROR_STOP=1 -c "
      UPDATE profiles                                SET organization_id='${ORG_ID}'::uuid WHERE organization_id<>'${ORG_ID}'::uuid;
      UPDATE profile_benchmarks                      SET organization_id='${ORG_ID}'::uuid WHERE organization_id<>'${ORG_ID}'::uuid;
      UPDATE profile_grafana_dashboards              SET organization_id='${ORG_ID}'::uuid WHERE organization_id<>'${ORG_ID}'::uuid;
      UPDATE provisioned_template_ds_compare_configs SET organization_id='${ORG_ID}'::uuid WHERE organization_id<>'${ORG_ID}'::uuid;
    " >/dev/null 2>&1 && echo "        provisioned rows reattached"
  docker compose restart perfana-api >/dev/null 2>&1 || true
  wait_for "$API_LOCAL/api/health" "Perfana API" 60
  TOKEN="$(get_token)"   # refresh: token now carries org membership

  # 6. Grafana service account + register instance in Perfana
  echo "    - Creating Grafana service-account token"
  sa_id="$(curl -s -X POST "$GRAFANA_LOCAL/api/serviceaccounts" \
    -u "${GRAFANA_ADMIN_USER:-perfana}:${GRAFANA_ADMIN_PASSWORD}" \
    -H 'Content-Type: application/json' -d '{"name":"perfana","role":"Admin"}' | jq -r '.id // empty')"
  [[ -z "$sa_id" ]] && sa_id="$(curl -sf "$GRAFANA_LOCAL/api/serviceaccounts/search" \
    -u "${GRAFANA_ADMIN_USER:-perfana}:${GRAFANA_ADMIN_PASSWORD}" \
    | jq -r '.serviceAccounts[]? | select(.name=="perfana") | .id' 2>/dev/null | head -1)"
  GRAFANA_TOKEN=""
  if [[ -n "$sa_id" ]]; then
    GRAFANA_TOKEN="$(curl -s -X POST "$GRAFANA_LOCAL/api/serviceaccounts/$sa_id/tokens" \
      -u "${GRAFANA_ADMIN_USER:-perfana}:${GRAFANA_ADMIN_PASSWORD}" \
      -H 'Content-Type: application/json' -d "{\"name\":\"perfana-$(date +%s 2>/dev/null || echo token)\"}" \
      | jq -r '.key // empty')"
  fi
  [[ -n "$GRAFANA_TOKEN" ]] && echo "        token created" || echo "        WARNING: no Grafana token (registering without key)"

  echo "    - Registering Grafana instance in Perfana"
  existing="$(curl -sf "$API_LOCAL/api/grafana-instances" -H "Authorization: Bearer $TOKEN" | jq -r '.[0].id // empty')"
  if [[ -z "$existing" ]]; then
    curl -sf -X POST "$API_LOCAL/api/grafana-instances" -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/json' -d "{
        \"label\":\"Grafana\",
        \"clientUrl\":\"$SCHEME://$HOST:$GRAFANA_PORT\",
        \"serverUrl\":\"http://grafana:3000\",
        \"orgId\":\"1\",
        \"apiKey\":\"${GRAFANA_TOKEN}\",
        \"organizationId\":\"$ORG_ID\"
      }" >/dev/null 2>&1 && echo "        registered" || echo "        WARNING: could not register Grafana"
  elif [[ -n "$GRAFANA_TOKEN" ]]; then
    curl -sf -X PATCH "$API_LOCAL/api/grafana-instances/$existing" -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/json' -d "{\"apiKey\":\"$GRAFANA_TOKEN\"}" >/dev/null 2>&1 \
      && echo "        updated existing instance" || echo "        instance exists (key unchanged)"
  fi

  # 7. Perfana API key (for load generators submitting results)
  echo "    - Creating Perfana API key"
  API_KEY="$(curl -sf "$API_LOCAL/api/api-keys" -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' -d '{"ttl":"1y","description":"default"}' | jq -r '.token // empty')"
fi

echo
echo "=================================================================="
echo " Bootstrap complete."
echo "   Perfana UI : $SCHEME://$HOST:$WEB_PORT   (login: $PERFANA_USER)"
echo "   Grafana    : $SCHEME://$HOST:$GRAFANA_PORT"
if [[ -n "${API_KEY:-}" ]]; then
  echo
  echo "   Perfana API key (store securely - shown once):"
  echo "     $API_KEY"
fi
echo "=================================================================="
