# Adding Grafana Integration

This guide explains how to connect a Grafana instance to Perfana so dashboards are automatically synced and linked to your test runs.

## Prerequisites

- A running Grafana instance (v9+ recommended)
- A Grafana **Service Account token** (preferred) or basic auth credentials
- The Grafana instance must be network-reachable from the Perfana API server

## Step 1: Create a Grafana Service Account Token

1. In Grafana, go to **Administration > Service Accounts**
2. Click **Add service account**
3. Give it a name (e.g. `perfana-sync`) and the **Viewer** role (Editor if you want snapshot support)
4. Click **Add service account token** and copy the generated token (format: `glsa_...`)

## Step 2: Add the Grafana Instance in Perfana

### Via the UI

1. Navigate to **Integrations** in the Perfana sidebar
2. Click **Add Grafana Instance**
3. Fill in the form:

| Field | Required | Description |
|-------|----------|-------------|
| **Label** | Yes | A unique name for this instance (e.g. `Production Grafana`) |
| **Client URL** | Yes | The URL used to access Grafana from the browser (e.g. `https://grafana.example.com`) |
| **Server URL** | No | Internal URL if the API server uses a different address to reach Grafana |
| **Org ID** | Yes | Grafana Organization ID (default: `1`) |
| **API Key** | No | Service Account token (`glsa_...`) — recommended auth method |
| **Username** | No | For basic auth (alternative to API key) |
| **Password** | No | For basic auth (alternative to API key) |
| **Snapshot Instance** | No | Enable if this instance is used for storing dashboard snapshots |

4. Click **Test Connection** to verify Perfana can reach Grafana
5. Click **Save**

![[Pasted image 20260302204848.png]]

### Via the API

```bash
curl -X POST https://your-perfana/api/grafana-instances \
  -H "Authorization: Bearer <your-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "label": "Production Grafana",
    "clientUrl": "https://grafana.example.com",
    "orgId": "1",
    "apiKey": "glsa_your_service_account_token"
  }'
```

#### Test connection before saving

```bash
curl -X POST https://your-perfana/api/grafana-instances/test-connection \
  -H "Authorization: Bearer <your-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "clientUrl": "https://grafana.example.com",
    "orgId": "1",
    "apiKey": "glsa_your_service_account_token"
  }'
```

## Step 3: Dashboard Sync

Once a Grafana instance is added, the **Grafana Sync Service** automatically:

1. **Discovers dashboards** — fetches all dashboards from the instance
2. **Extracts metadata** — parses templating variables, panels, and tags
3. **Stores them in Perfana** — dashboards appear in the instance's expanded view
4. **Keeps them in sync** — checks for changes every 30 seconds by default
5. **Restores deleted dashboards** — if a dashboard is accidentally removed from Grafana, it can be restored from the stored copy

No manual action is needed — sync starts automatically after the instance is saved.

## Step 4: Link Dashboards to Your System

Application Dashboards connect Grafana dashboards to a specific **system under test** and **test environment**. This enables Perfana to render the right dashboards during test runs.

### Auto-Configuration

The sync service automatically detects common dashboard variables and links dashboards to systems:

- `system_under_test` / `application`
- `test_environment` / `environment`
- `service` / `workload`

### Manual Configuration

If auto-detection doesn't match your setup, create an application dashboard manually:

```bash
curl -X POST https://your-perfana/api/grafana/application-dashboards \
  -H "Authorization: Bearer <your-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "systemUnderTestId": "<system-uuid>",
    "testEnvironment": "test",
    "grafanaInstanceId": "<instance-uuid>",
    "grafanaDashboardId": "<dashboard-uuid>",
    "dashboardLabel": "JVM Metrics - MyApp"
  }'
```

## Available Dashboard Templates

Perfana ships with 21 built-in dashboard templates:

| Category | Dashboards |
|----------|------------|
| **Load Testing** | Gatling Overview, JMeter Overview, JMeter Request Performance, K6 HTTP, Neoload, Request Duration |
| **Infrastructure** | System Under Test, Containers, Kubernetes Namespace, Kubernetes Pod |
| **JVM & Application** | Micrometer JVM, JVM Memory Usage, Afterburner Database |
| **HTTP & Network** | HTTP Client Requests, HTTP Server Requests, HTTP Request Duration |
| **Connection Pools** | Hikari Connection Pool, HTTP Connection Pool |
| **Advanced** | Span Metrics, Dynatrace USQL, Loki, Trends |

## Troubleshooting

| Problem | Solution |
|---------|----------|
| **Test Connection fails** | Verify the URL is reachable from the Perfana server. If using a `serverUrl`, ensure it resolves correctly. |
| **No dashboards appear after sync** | Check that the API key/credentials have at least Viewer permissions in the correct Grafana org. |
| **Dashboards not linked to test runs** | Verify your dashboard templating variables use recognized names (`system_under_test`, `test_environment`). |
| **401 Unauthorized from Perfana API** | Ensure your Bearer token is valid. For the UI, check that Keycloak session hasn't expired. |

## Authentication Notes

- **UI users** authenticate via Keycloak SSO — tokens are managed automatically
- **API users** can use either a Keycloak JWT or a Perfana API key as the Bearer token
- Adding/editing/deleting Grafana instances requires **org-admin** role in the assigned organization
