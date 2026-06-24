#!/bin/bash
# ================================================================================================
# Perfana Demo Initialization Script
# ================================================================================================
# First-time setup for the full Perfana demo environment.
# Starts all infrastructure + Perfana services, creates an API key,
# and runs baseline load tests.
#
# Prerequisites:
#   - Docker and Docker Compose installed
#   - jq installed (for API key extraction)
# ================================================================================================

set -o pipefail
set -o nounset

COMPOSE_FILE="docker-compose.yml"
ENABLE_DYNATRACE_MOCK=false

# Parse flags
for arg in "$@"; do
  case $arg in
    --dynatrace-mock) ENABLE_DYNATRACE_MOCK=true ;;
  esac
done

# Set environment variables with defaults
export SUT_VERSION=${SUT_VERSION:-2.4.3-good-baseline}
export POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-perfana}
export KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN:-admin}
export KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD:-admin}

PERFANA_USER="admin@perfana.io"
PERFANA_PASSWORD="Test@1234"

echo "Initializing Perfana Demo Environment..."
echo ""

# Start core infrastructure first
echo "[1/8] Starting core databases..."
docker compose -f "$COMPOSE_FILE" up -d postgres redis mariadb influxdb

# Run database migrations (waits for postgres healthy, then exits)
echo "[2/8] Running database migrations..."
docker compose -f "$COMPOSE_FILE" up perfana-migration
MIGRATION_EXIT=$?
if [ $MIGRATION_EXIT -ne 0 ]; then
  echo "ERROR: Database migration failed (exit code $MIGRATION_EXIT). Check logs:"
  echo "  docker compose -f $COMPOSE_FILE logs perfana-migration"
  exit 1
fi

# Start authentication
echo "[3/8] Starting authentication..."
docker compose -f "$COMPOSE_FILE" up -d keycloak-theme-provider
docker compose -f "$COMPOSE_FILE" up -d keycloak

# Wait for Keycloak to be healthy (health check polls /health/ready, so healthy = realm imported)
echo "       Waiting for Keycloak..."
for i in $(seq 1 90); do
  kc_status=$(docker compose -f "$COMPOSE_FILE" ps keycloak --format "{{.Status}}" 2>/dev/null)
  if echo "$kc_status" | grep -q "healthy"; then
    break
  fi
  if [ "$i" -eq 90 ]; then
    echo "ERROR: Keycloak did not become healthy within 3 minutes"
    exit 1
  fi
  sleep 2
done

# Configure Keycloak admin CLI session
docker exec perfana-keycloak /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 --realm master --user "${KEYCLOAK_ADMIN}" --password "${KEYCLOAK_ADMIN_PASSWORD}" 2>/dev/null

# Get the user ID for admin@perfana.io
kc_user_id=$(docker exec perfana-keycloak /opt/keycloak/bin/kcadm.sh get users -r perfana-prod \
  -q "username=${PERFANA_USER}" --fields id 2>/dev/null | jq -r '.[0].id')

if [ -z "$kc_user_id" ] || [ "$kc_user_id" = "null" ]; then
  echo "       WARNING: Could not find user ${PERFANA_USER} in Keycloak"
else
  # Set password using --userid (--username variant silently fails)
  docker exec perfana-keycloak /opt/keycloak/bin/kcadm.sh set-password \
    -r perfana-prod --userid "$kc_user_id" --new-password "${PERFANA_PASSWORD}" 2>/dev/null \
    && echo "       Test user ready: ${PERFANA_USER} / ${PERFANA_PASSWORD}" \
    || echo "       WARNING: Could not set test user password"
fi

# Enable direct access grants on perfana-web client (needed for programmatic token requests)
kc_client_uuid=$(docker exec perfana-keycloak /opt/keycloak/bin/kcadm.sh get clients -r perfana-prod \
  --fields id,clientId 2>/dev/null | jq -r '.[] | select(.clientId=="perfana-web") | .id')

if [ -n "$kc_client_uuid" ] && [ "$kc_client_uuid" != "null" ]; then
  docker exec perfana-keycloak /opt/keycloak/bin/kcadm.sh update "clients/$kc_client_uuid" \
    -r perfana-prod -s directAccessGrantsEnabled=true 2>/dev/null
fi

# Disable OTP in direct grant flow (breaks programmatic auth)
docker exec perfana-keycloak /opt/keycloak/bin/kcadm.sh get "authentication/flows/direct%20grant/executions" \
  -r perfana-prod 2>/dev/null | jq -r '.[] | select(.providerId=="direct-grant-validate-otp") | .id' | while read -r otp_exec_id; do
  if [ -n "$otp_exec_id" ]; then
    docker exec perfana-keycloak /opt/keycloak/bin/kcadm.sh update \
      "authentication/flows/direct%20grant/executions" -r perfana-prod \
      -b "{\"id\":\"$otp_exec_id\",\"requirement\":\"DISABLED\",\"providerId\":\"direct-grant-validate-otp\"}" 2>/dev/null
  fi
done

# Start Perfana services
echo "[4/8] Starting Perfana services..."
docker compose -f "$COMPOSE_FILE" up -d perfana-api
docker compose -f "$COMPOSE_FILE" up -d perfana-web
docker compose -f "$COMPOSE_FILE" up -d perfana-worker
docker compose -f "$COMPOSE_FILE" up -d perfana-grafana-sync
docker compose -f "$COMPOSE_FILE" up -d perfana-report

# Start observability stack
echo "[5/8] Starting observability stack..."
docker compose -f "$COMPOSE_FILE" up -d grafana prometheus alertmanager tempo pyroscope loki telegraf

# Start demo applications
echo "[6/8] Starting demo applications..."
docker compose -f "$COMPOSE_FILE" up -d afterburner-fe afterburner-be wiremock

if [ "$ENABLE_DYNATRACE_MOCK" = "true" ]; then
  echo "       Starting Dynatrace mock..."
  docker compose -f "$COMPOSE_FILE" --profile dynatrace-mock up -d dynatrace-mock
fi

# Wait for Perfana API and Grafana, configure integrations, create API key
echo "[7/8] Waiting for services and configuring integrations..."
echo "       Waiting for Perfana API to be ready..."
for i in $(seq 1 60); do
  if curl -sf http://localhost:3001/api/health > /dev/null 2>&1; then
    echo "       Perfana API is ready."
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "       WARNING: Perfana API did not become ready within 120 seconds"
  fi
  sleep 2
done

echo "       Waiting for Grafana to be ready..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:3000/api/health > /dev/null 2>&1; then
    echo "       Grafana is ready."
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "       WARNING: Grafana did not become ready within 60 seconds"
  fi
  sleep 2
done

# Obtain a JWT token from Keycloak
echo "       Authenticating with Keycloak..."
auth_token=$(curl -sf 'http://localhost:8080/realms/perfana-prod/protocol/openid-connect/token' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=password' \
  -d 'client_id=perfana-web' \
  --data-urlencode "username=${PERFANA_USER}" \
  --data-urlencode "password=${PERFANA_PASSWORD}" | jq -r '.access_token' 2>/dev/null)

if [ -z "$auth_token" ] || [ "$auth_token" = "null" ]; then
  echo "       WARNING: Could not authenticate with Keycloak. Integrations will not be configured."
  echo "       You may need to configure them manually."
else
  # Create Demo organization
  echo "       Creating Demo organization..."
  org_id=$(curl -sf -X POST 'http://localhost:3001/api/organizations' \
    -H "Authorization: Bearer $auth_token" \
    -H 'Content-Type: application/json' \
    -d '{"name": "Demo", "description": "Demo organization for performance testing"}' | jq -r '.id' 2>/dev/null)

  if [ -z "$org_id" ] || [ "$org_id" = "null" ]; then
    # Organization may already exist, find it
    org_id=$(curl -sf 'http://localhost:3001/api/organizations' \
      -H "Authorization: Bearer $auth_token" | jq -r '.[] | select(.name=="Demo") | .id' 2>/dev/null)
  fi

  if [ -n "$org_id" ] && [ "$org_id" != "null" ]; then
    echo "       Demo organization ready: $org_id"

    # Add current user to Demo organization as org-admin
    user_kc_id=$(echo "$auth_token" | cut -d'.' -f2 | base64 -d 2>/dev/null | jq -r '.sub')
    if [ -n "$user_kc_id" ] && [ "$user_kc_id" != "null" ]; then
      is_member=$(curl -sf "http://localhost:3001/api/organizations/$org_id/members" \
        -H "Authorization: Bearer $auth_token" | jq -r "[.[] | select(.user_id==\"$user_kc_id\")] | length" 2>/dev/null)

      if [ "$is_member" = "0" ] || [ -z "$is_member" ]; then
        curl -sf -X POST "http://localhost:3001/api/organizations/$org_id/members" \
          -H "Authorization: Bearer $auth_token" \
          -H 'Content-Type: application/json' \
          -d "{\"userId\": \"$user_kc_id\", \"roles\": [\"org-admin\"]}" > /dev/null 2>&1 \
          && echo "       User ${PERFANA_USER} added to Demo organization" \
          || echo "       WARNING: Could not add user to Demo organization"
      fi
    fi

    # Provisioning YAMLs ship with a placeholder org id. The provisioning
    # service that runs on perfana-api startup happily inserts rows under
    # that id, but RLS hides them from every real user. Rewrite the YAMLs
    # to the real Demo org, reattach any rows that were already inserted
    # under the placeholder, then restart perfana-api so subsequent boots
    # are idempotent against the patched files.
    echo "       Patching provisioning YAMLs with Demo org id..."
    for f in ./provisioning/profiles.yaml \
             ./provisioning/profile_benchmarks.yaml \
             ./provisioning/profile_grafana_dashboards.yaml \
             ./provisioning/template_ds_compare_configs.yaml; do
      if [ -f "$f" ]; then
        sed -i.bak "s|^organizationId:.*|organizationId: ${org_id}|" "$f" && rm -f "${f}.bak"
      fi
    done

    docker exec perfana-postgres psql -U perfana -d perfana -v ON_ERROR_STOP=1 -c "
        UPDATE profiles                                SET organization_id = '${org_id}'::uuid WHERE organization_id <> '${org_id}'::uuid;
        UPDATE profile_benchmarks                      SET organization_id = '${org_id}'::uuid WHERE organization_id <> '${org_id}'::uuid;
        UPDATE profile_grafana_dashboards              SET organization_id = '${org_id}'::uuid WHERE organization_id <> '${org_id}'::uuid;
        UPDATE provisioned_template_ds_compare_configs SET organization_id = '${org_id}'::uuid WHERE organization_id <> '${org_id}'::uuid;
      " > /dev/null && echo "       Provisioned rows reattached to Demo org."

    echo "       Restarting perfana-api to re-run provisioning against patched YAMLs..."
    docker compose restart perfana-api > /dev/null
    for i in $(seq 1 60); do
      if curl -sf http://localhost:3001/api/health > /dev/null 2>&1; then
        echo "       Perfana API is ready."
        break
      fi
      if [ "$i" -eq 60 ]; then
        echo "       WARNING: Perfana API did not become ready within 120 seconds"
      fi
      sleep 2
    done
  else
    echo "       WARNING: Could not create Demo organization"
  fi

  # Re-authenticate so the JWT picks up the newly-assigned org membership
  auth_token=$(curl -sf 'http://localhost:8080/realms/perfana-prod/protocol/openid-connect/token' \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -d 'grant_type=password' \
    -d 'client_id=perfana-web' \
    --data-urlencode "username=${PERFANA_USER}" \
    --data-urlencode "password=${PERFANA_PASSWORD}" | jq -r '.access_token' 2>/dev/null)

  # Create Perfana API key early — it doesn't expire like the JWT (1y TTL)
  # If a "demo" key already exists (e.g. re-running init-demo.sh on the same DB),
  # delete it first so we can get the fresh plaintext token back.
  echo "       Creating Perfana API key..."
  _existing_key_id=$(curl -sf "http://localhost:3001/api/api-keys?organizationId=${org_id}" \
    -H "Authorization: Bearer $auth_token" \
    | jq -r '.[] | select(.description == "demo") | .id // empty' 2>/dev/null | head -1)
  if [ -n "$_existing_key_id" ] && [ "$_existing_key_id" != "null" ]; then
    echo "       Found existing demo API key ($_existing_key_id) — deleting to rotate..."
    curl -sf -X DELETE "http://localhost:3001/api/api-keys/$_existing_key_id" \
      -H "Authorization: Bearer $auth_token" >/dev/null 2>&1 \
      && echo "       Deleted stale demo API key" \
      || echo "       WARNING: Could not delete stale API key; creation may fail with 409"
  fi
  api_key=$(curl -sf 'http://localhost:3001/api/api-keys' \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $auth_token" \
    -d '{"ttl": "1y", "description": "demo"}' | jq -r '.token // empty' 2>/dev/null)

  if [ -n "$api_key" ] && [ "$api_key" != "null" ]; then
    # Replace existing API key in loadtest pom.xml and jmeter perfana.yaml
    if [ -f ./loadtest/pom.xml ]; then
      sed -i.bak "s|<apiKey>[^<]*</apiKey>|<apiKey>$api_key</apiKey>|" ./loadtest/pom.xml && rm -f ./loadtest/pom.xml.bak
      echo "       API key injected into loadtest/pom.xml"
    fi
    if [ -f ./jmeter/perfana.yaml ]; then
      sed -i.bak "s|apiKey:.*|apiKey: \"$api_key\"|" ./jmeter/perfana.yaml && rm -f ./jmeter/perfana.yaml.bak
      echo "       API key injected into jmeter/perfana.yaml"
    fi
  else
    echo "       WARNING: Could not create API key. You may need to configure it manually."
  fi

  # Create Grafana service account and API token
  echo "       Creating Grafana service account..."
  grafana_token=""

  # Try to create a new service account
  sa_response=$(curl -s -X POST 'http://localhost:3000/api/serviceaccounts' \
    -u perfana:perfana \
    -H 'Content-Type: application/json' \
    -d '{"name":"perfana","role":"Admin"}')
  grafana_sa_id=$(echo "$sa_response" | jq -r '.id // empty' 2>/dev/null)

  # If creation failed (already exists), find the existing one
  if [ -z "$grafana_sa_id" ]; then
    grafana_sa_id=$(curl -sf 'http://localhost:3000/api/serviceaccounts/search' \
      -u perfana:perfana | jq -r '.serviceAccounts[] | select(.name=="perfana") | .id' 2>/dev/null)
  fi

  if [ -n "$grafana_sa_id" ]; then
    # Try to create a token (may fail if one with this name already exists)
    token_response=$(curl -s -X POST "http://localhost:3000/api/serviceaccounts/$grafana_sa_id/tokens" \
      -u perfana:perfana \
      -H 'Content-Type: application/json' \
      -d '{"name":"perfana-token"}')
    grafana_token=$(echo "$token_response" | jq -r '.key // empty' 2>/dev/null)

    if [ -n "$grafana_token" ]; then
      echo "       Grafana service account ready (token: ${grafana_token:0:12}...)"
    else
      echo "       WARNING: Grafana service account exists but could not create token (may already exist)"
      echo "       The Grafana instance will be registered without an API key"
    fi
  else
    echo "       WARNING: Could not create or find Grafana service account"
  fi

  # Register Grafana instance in Perfana
  echo "       Registering Grafana instance..."
  existing_grafana=$(curl -sf 'http://localhost:3001/api/grafana-instances' \
    -H "Authorization: Bearer $auth_token" | jq -r '.[0].id' 2>/dev/null)

  if [ -z "$existing_grafana" ] || [ "$existing_grafana" = "null" ]; then
    grafana_instance_id=$(curl -sf -X POST 'http://localhost:3001/api/grafana-instances' \
      -H "Authorization: Bearer $auth_token" \
      -H 'Content-Type: application/json' \
      -d "{
        \"label\": \"Demo\",
        \"clientUrl\": \"http://localhost:3000\",
        \"serverUrl\": \"http://grafana:3000\",
        \"orgId\": \"1\",
        \"apiKey\": \"${grafana_token:-}\",
        \"organizationId\": \"${org_id}\"
      }" | jq -r '.id' 2>/dev/null)

    if [ -n "$grafana_instance_id" ] && [ "$grafana_instance_id" != "null" ]; then
      echo "       Grafana instance registered: $grafana_instance_id"
    else
      echo "       WARNING: Could not register Grafana instance"
    fi
  else
    # Instance exists - update it with the API key if we have a new token
    if [ -n "$grafana_token" ]; then
      curl -sf -X PATCH "http://localhost:3001/api/grafana-instances/$existing_grafana" \
        -H "Authorization: Bearer $auth_token" \
        -H 'Content-Type: application/json' \
        -d "{\"apiKey\": \"$grafana_token\"}" > /dev/null 2>&1 \
        && echo "       Grafana instance updated with API key: $existing_grafana" \
        || echo "       Grafana instance already exists: $existing_grafana (could not update API key)"
    else
      echo "       Grafana instance already exists: $existing_grafana"
    fi
  fi

  # Register Tempo tracing instance
  echo "       Registering Tempo tracing instance..."
  existing_tempo=$(curl -sf 'http://localhost:3001/api/tracing-instances' \
    -H "Authorization: Bearer $auth_token" | jq -r '.[0].id' 2>/dev/null)

  if [ -z "$existing_tempo" ] || [ "$existing_tempo" = "null" ]; then
    tempo_instance_id=$(curl -sf -X POST 'http://localhost:3001/api/tracing-instances' \
      -H "Authorization: Bearer $auth_token" \
      -H 'Content-Type: application/json' \
      -d "{
        \"label\": \"Tempo\",
        \"tracingUrl\": \"http://localhost:3000/d/tempo-traces/tempo-traces\",
        \"tracingApiUrl\": \"http://tempo:3200\",
        \"tracingUi\": \"tempo\",
        \"tracingIframeAllowed\": true,
        \"organizationId\": \"${org_id}\"
      }" | jq -r '.id' 2>/dev/null)

    if [ -n "$tempo_instance_id" ] && [ "$tempo_instance_id" != "null" ]; then
      echo "       Tempo instance registered: $tempo_instance_id"
    else
      echo "       WARNING: Could not register Tempo instance"
    fi
  else
    echo "       Tempo instance already exists: $existing_tempo"
  fi

  # Register Pyroscope profiling instance
  echo "       Registering Pyroscope profiling instance..."
  existing_pyroscope=$(curl -sf 'http://localhost:3001/api/pyroscope-instances' \
    -H "Authorization: Bearer $auth_token" | jq -r '.[0].id' 2>/dev/null)

  if [ -z "$existing_pyroscope" ] || [ "$existing_pyroscope" = "null" ]; then
    pyroscope_instance_id=$(curl -sf -X POST 'http://localhost:3001/api/pyroscope-instances' \
      -H "Authorization: Bearer $auth_token" \
      -H 'Content-Type: application/json' \
      -d "{
        \"label\": \"Pyroscope\",
        \"pyroscopeUrl\": \"http://localhost:3000/a/grafana-pyroscope-app/explore\",
        \"backendUrl\": \"http://pyroscope:4040\",
        \"pyroscopeStandAlone\": false,
        \"organizationId\": \"${org_id}\"
      }" | jq -r '.id' 2>/dev/null)

    if [ -n "$pyroscope_instance_id" ] && [ "$pyroscope_instance_id" != "null" ]; then
      echo "       Pyroscope instance registered: $pyroscope_instance_id"
    else
      echo "       WARNING: Could not register Pyroscope instance"
    fi
  else
    echo "       Pyroscope instance already exists: $existing_pyroscope"
  fi

  # Register Dynatrace mock instance (only when --dynatrace-mock flag is set)
  if [ "$ENABLE_DYNATRACE_MOCK" = "true" ]; then
    echo "       Registering Dynatrace mock instance..."
    existing_dynatrace=$(curl -sf 'http://localhost:3001/api/dynatrace' \
      -H "Authorization: Bearer $auth_token" | jq -r '.[0].id' 2>/dev/null)

    if [ -z "$existing_dynatrace" ] || [ "$existing_dynatrace" = "null" ]; then
      dynatrace_instance_id=$(curl -sf -X POST 'http://localhost:3001/api/dynatrace' \
        -H "Authorization: Bearer $auth_token" \
        -H 'Content-Type: application/json' \
        -d "{
          \"label\": \"Dynatrace Mock\",
          \"host\": \"http://dynatrace-mock:8080\",
          \"apiToken\": \"mock-api-token\",
          \"platformApiToken\": \"mock-platform-token\",
          \"dynatraceType\": \"saas\",
          \"organizationId\": \"${org_id}\"
        }" | jq -r '.id' 2>/dev/null)

      if [ -n "$dynatrace_instance_id" ] && [ "$dynatrace_instance_id" != "null" ]; then
        echo "       Dynatrace mock instance registered: $dynatrace_instance_id"
      else
        echo "       WARNING: Could not register Dynatrace mock instance"
      fi
    else
      echo "       Dynatrace mock instance already exists: $existing_dynatrace"
    fi
  fi

  # ──────────────────────────────────────────────────────────────────────────────────────────
  # Create the System Under Test with pre-seeded environment and workload so that all seed
  # data (tracing, profiling, Dynatrace mappings, ADAPT mode) can be configured before the
  # first test run starts. The load test plugin registers runs against this pre-existing SUT.
  # ──────────────────────────────────────────────────────────────────────────────────────────
  echo "       Creating System Under Test (PerfanaWebshop)..."
  sut_id=$(curl -sf -X POST 'http://localhost:3001/api/systems-under-test' \
    -H "Authorization: Bearer $auth_token" \
    -H 'Content-Type: application/json' \
    -d "{
      \"name\": \"PerfanaWebshop\",
      \"description\": \"PerfanaWebshop\",
      \"organizationId\": \"${org_id}\",
      \"environments\": [{
        \"name\": \"acc\",
        \"workloads\": [{\"name\": \"loadTest\"}]
      }]
    }" | jq -r '.id' 2>/dev/null)

  if [ -z "$sut_id" ] || [ "$sut_id" = "null" ]; then
    # SUT may already exist — look it up
    sut_id=$(curl -sf 'http://localhost:3001/api/systems-under-test' \
      -H "Authorization: Bearer $auth_token" | jq -r '.[] | select(.name=="PerfanaWebshop") | .id' 2>/dev/null)
  fi

  if [ -n "$sut_id" ] && [ "$sut_id" != "null" ]; then
    echo "       System Under Test ready: $sut_id"

    # No need to pre-set BASELINE: the API forces BASELINE for the first run of a
    # sut/test-environment/workload combination automatically (perfana#407).

    tempo_id=$(curl -sf 'http://localhost:3001/api/tracing-instances' \
      -H "Authorization: Bearer $auth_token" | jq -r '.[0].id' 2>/dev/null)
    pyroscope_id=$(curl -sf 'http://localhost:3001/api/pyroscope-instances' \
      -H "Authorization: Bearer $auth_token" | jq -r '.[0].id' 2>/dev/null)

    # Configure tracing services (Tempo) for afterburner-fe
    if [ -n "$tempo_id" ] && [ "$tempo_id" != "null" ]; then
      ts_http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST 'http://localhost:3001/api/tracing-services' \
        -H "Authorization: Bearer $auth_token" \
        -H 'Content-Type: application/json' \
        -d "{
          \"systemUnderTestId\": \"$sut_id\",
          \"tracingInstanceId\": \"$tempo_id\",
          \"serviceNames\": [\"afterburner-fe\"]
        }")
      if [ "$ts_http_code" -ge 200 ] && [ "$ts_http_code" -lt 300 ] 2>/dev/null; then
        echo "       Tracing services configured for afterburner-fe"
      else
        # The API (≤0.2.47) has a bug where TracingServicesService does not set
        # organization_id before saving, so the RLS WITH CHECK rejects the INSERT.
        # Fall back to a direct DB insert until a fixed API version is available.
        docker exec perfana-postgres psql -U perfana -d perfana -v ON_ERROR_STOP=1 -c "
          INSERT INTO tracing_services (system_under_test_id, tracing_instance_id, service_names, organization_id, created_by, updated_by)
          SELECT '${sut_id}'::uuid, '${tempo_id}'::uuid, ARRAY['afterburner-fe'], '${org_id}'::uuid, '${user_kc_id}', '${user_kc_id}'
          WHERE NOT EXISTS (
            SELECT 1 FROM tracing_services
            WHERE system_under_test_id = '${sut_id}'::uuid
              AND tracing_instance_id  = '${tempo_id}'::uuid
          );" > /dev/null 2>&1 \
          && echo "       Tracing services configured for afterburner-fe" \
          || echo "       WARNING: Could not configure tracing services (API code=$ts_http_code)"
      fi
    fi

    # Configure Pyroscope profiling for afterburner-fe
    if [ -n "$pyroscope_id" ] && [ "$pyroscope_id" != "null" ]; then
      curl -sf -X PATCH "http://localhost:3001/api/systems-under-test/$sut_id/pyroscope" \
        -H "Authorization: Bearer $auth_token" \
        -H 'Content-Type: application/json' \
        -d "{
          \"pyroscope_instance_id\": \"$pyroscope_id\",
          \"pyroscope_configurations\": [
            {\"application\": \"afterburner-fe\", \"profiler\": \"process_cpu:cpu:nanoseconds:cpu:nanoseconds\"},
            {\"application\": \"afterburner-fe\", \"profiler\": \"memory:alloc_in_new_tlab_bytes:bytes:space:bytes\"}
          ]
        }" > /dev/null 2>&1 \
        && echo "       Pyroscope profiling configured for afterburner-fe" \
        || echo "       Pyroscope profiling could not be configured"
    fi

    # Configure Dynatrace entity mappings (only when --dynatrace-mock flag is set)
    if [ "$ENABLE_DYNATRACE_MOCK" = "true" ]; then
      dynatrace_id=$(curl -sf 'http://localhost:3001/api/dynatrace' \
        -H "Authorization: Bearer $auth_token" | jq -r '.[0].id' 2>/dev/null)

      if [ -n "$dynatrace_id" ] && [ "$dynatrace_id" != "null" ]; then
        curl -sf -X POST 'http://localhost:3001/api/dynatrace/entities/mappings' \
          -H "Authorization: Bearer $auth_token" \
          -H 'Content-Type: application/json' \
          -d "{
            \"dynatraceConfigId\": \"$dynatrace_id\",
            \"systemUnderTestId\": \"$sut_id\",
            \"entityId\": \"HOST-123\",
            \"entityDisplayName\": \"afterburner-be\",
            \"entityType\": \"HOST\",
            \"testEnvironment\": \"acc\",
            \"workload\": \"loadTest\",
            \"level\": \"sut\"
          }" > /dev/null 2>&1 \
          && echo "       Dynatrace entity mapped: afterburner-be (HOST-123)" \
          || echo "       Dynatrace entity mapping already exists or could not be created: afterburner-be"

        curl -sf -X POST 'http://localhost:3001/api/dynatrace/entities/mappings' \
          -H "Authorization: Bearer $auth_token" \
          -H 'Content-Type: application/json' \
          -d "{
            \"dynatraceConfigId\": \"$dynatrace_id\",
            \"systemUnderTestId\": \"$sut_id\",
            \"entityId\": \"HOST-456\",
            \"entityDisplayName\": \"afterburner-fe\",
            \"entityType\": \"HOST\",
            \"testEnvironment\": \"acc\",
            \"workload\": \"loadTest\",
            \"level\": \"sut\"
          }" > /dev/null 2>&1 \
          && echo "       Dynatrace entity mapped: afterburner-fe (HOST-456)" \
          || echo "       Dynatrace entity mapping already exists or could not be created: afterburner-fe"

        curl -sf -X POST 'http://localhost:3001/api/dynatrace/entities/mappings' \
          -H "Authorization: Bearer $auth_token" \
          -H 'Content-Type: application/json' \
          -d "{
            \"dynatraceConfigId\": \"$dynatrace_id\",
            \"systemUnderTestId\": \"$sut_id\",
            \"entityId\": \"SERVICE-123\",
            \"entityDisplayName\": \"afterburner-be\",
            \"entityType\": \"SERVICE\",
            \"testEnvironment\": \"acc\",
            \"workload\": \"loadTest\",
            \"level\": \"sut\"
          }" > /dev/null 2>&1 \
          && echo "       Dynatrace entity mapped: afterburner-be (SERVICE-123)" \
          || echo "       Dynatrace entity mapping already exists or could not be created: afterburner-be service"

        curl -sf -X POST 'http://localhost:3001/api/dynatrace/entities/mappings' \
          -H "Authorization: Bearer $auth_token" \
          -H 'Content-Type: application/json' \
          -d "{
            \"dynatraceConfigId\": \"$dynatrace_id\",
            \"systemUnderTestId\": \"$sut_id\",
            \"entityId\": \"SERVICE-456\",
            \"entityDisplayName\": \"afterburner-fe\",
            \"entityType\": \"SERVICE\",
            \"testEnvironment\": \"acc\",
            \"workload\": \"loadTest\",
            \"level\": \"sut\"
          }" > /dev/null 2>&1 \
          && echo "       Dynatrace entity mapped: afterburner-fe (SERVICE-456)" \
          || echo "       Dynatrace entity mapping already exists or could not be created: afterburner-fe service"
      else
        echo "       WARNING: Dynatrace instance not found. Entity mappings not configured."
      fi
    fi
  else
    echo "       WARNING: Could not create System Under Test. Seed data not configured."
  fi

fi

# Start load testing containers
echo "[8/8] Starting load testing..."
docker compose -f "$COMPOSE_FILE" up -d loadtest jmetertest

echo ""
# ================================================================================================
# ADAPT Mode Strategy
# ------------------------------------------------------------------------------------------------
# ADAPT is Perfana's automated regression detection engine. The workload-level adapt mode
# controls how each new test run is evaluated:
#
#   BASELINE  — runs are auto-accepted into the control group (no regression check).
#               Use this while building up the reference dataset.
#   DEFAULT   — runs are compared against the last 10 successful baseline runs.
#               Regressions in response times, throughput, or resources are flagged.
#
# Strategy used in this init script:
#   Run 1   → BASELINE  — forced automatically by the API (perfana#407): the first run of a
#             sut/test-environment/workload combination has nothing to compare against, so it is
#             always seeded as the control-group baseline regardless of requested mode.
#   Run 2+  → DEFAULT   — workload default; regression detection active.
#
# Because the API self-seeds the first baseline, the demo no longer pre-sets BASELINE mode. The
# three baseline (good) runs below still build run history; only run 1 anchors the control group,
# so runs 2-3 are already evaluated in DEFAULT (an intentionally thin early baseline).
#
# The SUT, test environment, and workload are pre-created above via POST /api/systems-under-test
# (with environments pre-seeded), so all seed data is configured before the first run starts.
# ================================================================================================
echo "Running first baseline load tests..."
./deploy-and-test-jmeter.sh baseline

echo "Running second baseline load tests..."
./deploy-and-test-jmeter.sh baseline

echo "Running third baseline load tests..."
./deploy-and-test-jmeter.sh baseline

# ================================================================================================
# Explicitly set ADAPT mode to DEFAULT (regression detection) before the injected-issue runs.
# The workload is already DEFAULT (run 1 was auto-seeded as BASELINE by the API), but we set it
# explicitly so regression detection is guaranteed active regardless of any prior workload state.
# In DEFAULT mode, ADAPT compares each new run against the last 10 successful baseline runs and
# automatically flags regressions in response times, throughput, or resource utilisation.
# ================================================================================================
echo "Ensuring ADAPT mode is DEFAULT (regression detection)..."

# Re-authenticate: the JWT (5 min lifespan) will have expired during the second load test
adapt_auth_token=$(curl -sf 'http://localhost:8080/realms/perfana-prod/protocol/openid-connect/token' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=password' \
  -d 'client_id=perfana-web' \
  --data-urlencode "username=${PERFANA_USER}" \
  --data-urlencode "password=${PERFANA_PASSWORD}" | jq -r '.access_token' 2>/dev/null)

if [ -n "$adapt_auth_token" ] && [ "$adapt_auth_token" != "null" ] \
   && [ -n "${sut_id:-}" ] && [ "$sut_id" != "null" ]; then
  adapt_result=$(curl -sf -X PUT 'http://localhost:3001/api/test-runs/workload-adapt-settings' \
    -H "Authorization: Bearer $adapt_auth_token" \
    -H 'Content-Type: application/json' \
    -d "{
      \"systemUnderTestId\": \"$sut_id\",
      \"testEnvironment\": \"acc\",
      \"workload\": \"loadTest\",
      \"adaptMode\": \"DEFAULT\"
    }" 2>/dev/null)
  if echo "$adapt_result" | jq -e '.adaptMode == "DEFAULT"' > /dev/null 2>&1; then
    echo "ADAPT mode set to DEFAULT (regression detection active)"
  else
    echo "WARNING: Could not set ADAPT mode to DEFAULT"
  fi
else
  echo "WARNING: Could not switch ADAPT mode to DEFAULT (auth or sut_id unavailable)"
fi

echo "Running load tests with issue..."
./deploy-and-test-jmeter.sh cpu

echo ""
echo "Perfana Demo Environment Ready!"
echo ""
echo "Login:"
echo "  User:                  ${PERFANA_USER}"
echo "  Password:              ${PERFANA_PASSWORD}"
echo ""
echo "Core Services:"
echo "  PostgreSQL:            localhost:5432"
echo "  PgBouncer:             localhost:6432  (optional, disabled by default - see README)"
echo "  Valkey:                localhost:6379"
echo "  Keycloak:              http://localhost:8080  (${KEYCLOAK_ADMIN}/${KEYCLOAK_ADMIN_PASSWORD})"
echo "  Perfana Web:           http://localhost:4000"
echo "  Perfana API:           http://localhost:3001"
echo "  Grafana:               http://localhost:3000  (perfana/perfana)"
echo ""
echo "Observability:"
echo "  Prometheus:            http://localhost:9090"
echo "  Alertmanager:          http://localhost:9093"
echo "  Tempo (Tracing):       http://localhost:3200"
echo "  Pyroscope (Profiling): http://localhost:4040"
echo "  Loki (Logs):           http://localhost:3100"
echo ""
echo "Demo Applications:"
echo "  Afterburner Frontend:  http://localhost:8090"
echo "  MariaDB:               localhost:3306"
echo "  InfluxDB:              http://localhost:8086"
echo "  Wiremock:              http://localhost:8060"
if [ "$ENABLE_DYNATRACE_MOCK" = "true" ]; then
echo "  Dynatrace Mock:        http://localhost:8061"
fi
echo ""
echo "Commands:"
echo "  docker compose -f $COMPOSE_FILE ps      # Check status"
echo "  docker compose -f $COMPOSE_FILE logs -f  # View logs"
echo ""

# Create Perfana MCP API key and print setup instructions
echo "============================================"
echo "  Perfana MCP (Model Context Protocol) Setup"
echo "============================================"
echo ""

# Use API key to create MCP key (no need to re-authenticate via Keycloak)
if [ -n "${api_key:-}" ] && [ "${api_key:-}" != "null" ]; then
  # Re-authenticate just for MCP key creation (API keys can't create other API keys)
  mcp_auth_token=$(curl -sf 'http://localhost:8080/realms/perfana-prod/protocol/openid-connect/token' \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -d 'grant_type=password' \
    -d 'client_id=perfana-web' \
    --data-urlencode "username=${PERFANA_USER}" \
    --data-urlencode "password=${PERFANA_PASSWORD}" | jq -r '.access_token' 2>/dev/null)

  if [ -n "$mcp_auth_token" ] && [ "$mcp_auth_token" != "null" ]; then
    mcp_api_key=$(curl -sf 'http://localhost:3001/api/api-keys' \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $mcp_auth_token" \
      -d '{"ttl": "1y", "description": "perfana-mcp"}' | jq -r '.token' 2>/dev/null)
  fi
fi

if [ -n "${mcp_api_key:-}" ] && [ "${mcp_api_key:-}" != "null" ]; then
  echo "  API key created (label: perfana-mcp): ${mcp_api_key:0:20}..."
  echo ""
  echo "  MCP config snippet (same for Claude Code .mcp.json and Claude Desktop):"
  echo ""
  echo "  {"
  echo "    \"mcpServers\": {"
  echo "      \"perfana\": {"
  echo "        \"command\": \"npx\","
  echo "        \"args\": [\"-y\", \"@perfana/mcp\"],"
  echo "        \"env\": {"
  echo "          \"PERFANA_API_URL\": \"http://localhost:3001/api\","
  echo "          \"PERFANA_API_KEY\": \"$mcp_api_key\""
  echo "        }"
  echo "      }"
  echo "    }"
  echo "  }"
  echo ""
  echo "  Claude Code  → add to .mcp.json in your project root"
  echo "  Claude Desktop → add to ~/Library/Application Support/Claude/claude_desktop_config.json"
  echo ""
  echo "  Or run this command to add it directly to Claude Code:"
  echo ""
  echo "  claude mcp add perfana -e PERFANA_API_URL=http://localhost:3001/api -e PERFANA_API_KEY=$mcp_api_key -- npx -y @perfana/mcp"
  echo ""
  echo "  Package: npm install @perfana/mcp   (requires Node >= 18)"
else
  echo "  WARNING: Could not create MCP API key."
  echo "  Create one manually in the Perfana UI under Settings > API Keys."
fi
echo ""

# Grafana MCP setup instructions
echo "============================================"
echo "  Grafana MCP (Model Context Protocol) Setup"
echo "============================================"
echo ""
if [ -n "${grafana_token:-}" ] && [ "${grafana_token:-}" != "null" ]; then
  echo "  MCP config snippet:"
  echo ""
  echo "  {"
  echo "    \"mcpServers\": {"
  echo "      \"grafana\": {"
  echo "        \"type\": \"stdio\","
  echo "        \"command\": \"uvx\","
  echo "        \"args\": [\"mcp-grafana\"],"
  echo "        \"env\": {"
  echo "          \"GRAFANA_URL\": \"http://localhost:3000\","
  echo "          \"GRAFANA_SERVICE_ACCOUNT_TOKEN\": \"$grafana_token\""
  echo "        }"
  echo "      }"
  echo "    }"
  echo "  }"
  echo ""
  echo "  Or run this command to add it directly to Claude Code:"
  echo ""
  echo "  claude mcp add grafana -e GRAFANA_URL=http://localhost:3000 -e GRAFANA_SERVICE_ACCOUNT_TOKEN=$grafana_token -- uvx mcp-grafana"
  echo ""
  echo "  Requirement: pip install uvx   (or: brew install uv)"
else
  echo "  WARNING: No Grafana API token available."
  echo "  Create a service account token in Grafana under Administration > Service Accounts,"
  echo "  then run:"
  echo "  claude mcp add grafana -e GRAFANA_URL=http://localhost:3000 -e GRAFANA_SERVICE_ACCOUNT_TOKEN=<token> -- uvx mcp-grafana"
fi
echo ""
