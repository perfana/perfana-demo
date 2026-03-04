# Adding Distributed Tracing (Tempo) Integration

This guide explains how to connect a Grafana Tempo instance to Perfana for distributed trace search, visualization, and correlation with test runs.

## Prerequisites

- A running Grafana Tempo instance (with HTTP API enabled)
- Tempo must expose the `/api/search`, `/api/traces/{traceId}`, and `/ready` endpoints
- Your application must be instrumented with OpenTelemetry and sending traces to Tempo
- Traces should include Perfana tags: `perfana-test-run-id` and `perfana-request-name`

## Step 1: Add a Tracing Instance in Perfana

### Via the UI

1. Navigate to **Integrations** in the Perfana sidebar
2. Click **Add Tracing Instance**
3. Fill in the form:

| Field | Required | Description |
|-------|----------|-------------|
| **Label** | Yes | A unique name (e.g. `Production Tempo`) |
| **Tracing URL** | Yes | The Grafana/Tempo UI URL for viewing traces in the browser (e.g. `https://grafana.example.com`) |
| **Tracing API URL** | No | Internal Tempo API URL used by the Perfana server for trace queries (e.g. `http://tempo:3200`). Required for trace search functionality. |
| **UI Type** | Yes | Select `tempo` (also supports `jaeger` and `elastic`) |
| **Iframe Allowed** | No | Enable if the tracing UI supports CORS and iframe embedding |

4. Click **Test Connection** to verify connectivity
5. Click **Save**

![[Pasted image 20260302210654.png]]
### Via the API

```bash
curl -X POST https://your-perfana/api/tracing-instances \
  -H "Authorization: Bearer <your-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "label": "Production Tempo",
    "tracingUrl": "https://grafana.example.com",
    "tracingApiUrl": "http://tempo:3200",
    "tracingUi": "tempo",
    "tracingIframeAllowed": false
  }'
```

#### Test connection before saving

```bash
curl -X POST https://your-perfana/api/tracing-instances/test-connection \
  -H "Authorization: Bearer <your-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "tracingUrl": "http://tempo:3200",
    "tracingUi": "tempo"
  }'
```

## Step 2: Configure Tracing Services

Tracing services link a tracing instance to a **system under test**, optionally scoped by environment and workload. This tells Perfana which services to query traces for during a test run.

### Hierarchical Configuration

Services can be configured at three levels of specificity:

| Level | Scope | Use case |
|-------|-------|----------|
| **System only** | All environments and workloads | Default tracing config for a system |
| **System + Environment** | Specific environment, all workloads | Environment-specific tracing |
| **System + Environment + Workload** | Fully scoped | Workload-specific tracing |

Perfana resolves the most specific match first, falling back to broader configurations.

### Via the UI

1. Go to **Systems > [Your System] > Configuration**
2. Find the **Distributed Tracing** section
3. Click **Add Tracing Service**
4. Select the tracing instance, configure the scope, and add service names
5. Click **Save**

![[Pasted image 20260303115353.png]]
### Via the API

```bash
curl -X POST https://your-perfana/api/tracing-services \
  -H "Authorization: Bearer <your-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "systemUnderTestId": "<system-uuid>",
    "testEnvironment": "test",
    "workload": "load-test",
    "tracingInstanceId": "<tracing-instance-uuid>",
    "serviceNames": ["user-service", "order-service", "payment-service"]
  }'
```

## Step 3: Instrument Your Application

For Perfana to correlate traces with test runs, your application must propagate two custom span attributes:

| Attribute | Description | Example |
|-----------|-------------|---------|
| `perfana-test-run-id` | The unique test run identifier | `my-app-load-test-20240115` |
| `perfana-request-name` | The request/transaction name | `Login\|POST /api/auth\|200` |

### OpenTelemetry Example (Java)

```java
Span.current()
    .setAttribute("perfana-test-run-id", testRunId)
    .setAttribute("perfana-request-name", requestName);
```

These attributes allow Perfana to build TraceQL queries like:

```
{
  resource.service.name="user-service" &&
  ."perfana-test-run-id" = "my-test-run" &&
  ."perfana-request-name" =~ "Login[|].*"
}
```

## Step 4: Search Traces from Test Runs

Once configured, Perfana can search for traces during or after a test run.

### Via the API

```bash
curl -X POST https://your-perfana/api/tempo/search \
  -H "Authorization: Bearer <your-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "tracingInstanceId": "<tracing-instance-uuid>",
    "serviceName": "user-service",
    "testRunId": "my-app-load-test-20240115",
    "scenario": "Login",
    "transaction": "POST /api/auth",
    "startTime": "2024-01-15T10:00:00Z",
    "endTime": "2024-01-15T11:00:00Z",
    "limit": 100
  }'
```

The response includes matching traces with duration, span count, and root service information.

## Supported Tracing Backends

While this guide focuses on Tempo, Perfana also supports:

| Backend | UI Type | Notes |
|---------|---------|-------|
| **Grafana Tempo** | `tempo` | Full support with TraceQL search, backend API URL for server-side queries |
| **Jaeger** | `jaeger` | Tag-based trace filtering via Jaeger UI |
| **Elastic APM** | `elastic` | KQL-based trace queries via Elastic UI |

## Tempo Infrastructure Example

A typical `docker-compose.yml` setup for Tempo:

```yaml
tempo:
  image: grafana/tempo:latest
  command: ["-config.file=/etc/tempo.yaml"]
  ports:
    - "3200:3200"   # Tempo HTTP API
    - "4317:4317"   # OTLP gRPC receiver
    - "4318:4318"   # OTLP HTTP receiver
  volumes:
    - ./tempo/tempo.yaml:/etc/tempo.yaml
```

In this setup:
- **Tracing URL**: `https://grafana.example.com` (Grafana UI with Tempo datasource)
- **Tracing API URL**: `http://tempo:3200` (direct Tempo API, used server-side by Perfana)

## Troubleshooting

| Problem | Solution |
|---------|----------|
| **Test Connection fails** | Verify Tempo's `/ready` endpoint is reachable from the Perfana server. Check the Tracing API URL, not the UI URL. |
| **No traces found** | Ensure your app sends `perfana-test-run-id` and `perfana-request-name` attributes. Verify service names match exactly. |
| **Trace search returns errors** | Check that Tempo's `/api/search` endpoint is enabled and accessible at the configured API URL. |
| **Iframe not loading** | Enable `tracingIframeAllowed` and configure CORS headers on the Tempo/Grafana server (`allow_embedding = true` in Grafana). |
| **Wrong traces returned** | Check the hierarchical resolution — a more specific config (system+env+workload) takes priority over a general one. |
