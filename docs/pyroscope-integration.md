# Adding Pyroscope Profiling Integration

This guide explains how to connect a Pyroscope instance to Perfana for continuous profiling, flamegraph analysis, and performance regression detection at the code level.

## Prerequisites

- A running Pyroscope instance (standalone or Grafana-embedded)
- Your application instrumented with a Pyroscope agent or OpenTelemetry profiling
- Network connectivity from the Perfana API server to Pyroscope

## Step 1: Add a Pyroscope Instance in Perfana

### Via the UI

1. Navigate to **Integrations** in the Perfana sidebar
2. Click **Add Pyroscope Instance**
3. Fill in the form:

| Field               | Required | Description                                                                                                           |
| ------------------- | -------- | --------------------------------------------------------------------------------------------------------------------- |
| **Label**           | Yes      | A unique name (e.g. `Production Pyroscope`)                                                                           |
| **Pyroscope URL**   | Yes      | The Pyroscope UI URL (e.g. `https://pyroscope.example.com` or the Grafana URL if embedded)                            |
| **Backend API URL** | No       | Direct Pyroscope API endpoint for server-side queries (e.g. `http://pyroscope:4040`). Needed for flamegraph analysis. |
| **Standalone Mode** | No       | Enable if Pyroscope runs independently (not embedded in Grafana)                                                      |

4. Click **Test Connection** to verify connectivity
5. Click **Save**

	![[Pasted image 20260303133400.png]]
### Via the API

```bash
curl -X POST https://your-perfana/api/pyroscope-instances \
  -H "Authorization: Bearer <your-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "label": "Production Pyroscope",
    "pyroscopeUrl": "https://pyroscope.example.com",
    "backendUrl": "http://pyroscope:4040",
    "pyroscopeStandAlone": true
  }'
```

#### Test connection before saving

```bash
curl -X POST https://your-perfana/api/pyroscope-instances/test-connection \
  -H "Authorization: Bearer <your-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "pyroscopeUrl": "http://pyroscope:4040"
  }'
```

## Step 2: Assign Pyroscope to a System Under Test

After creating the instance, link it to a system under test with the specific applications and profiler types to monitor.

### Via the UI

1. Go to **Systems > [Your System] > Configuration**
2. Find the **Profiling** section
3. Select your Pyroscope instance
4. Add one or more **application + profiler** combinations
5. Click **Save**

### Via the API

```bash
curl -X PUT https://your-perfana/api/systems-under-test/<system-uuid>/pyroscope-config \
  -H "Authorization: Bearer <your-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "pyroscope_instance_id": "<pyroscope-instance-uuid>",
    "pyroscope_configurations": [
      {
        "application": "my-app",
        "profiler": "process_cpu:cpu:nanoseconds:cpu:nanoseconds"
      },
      {
        "application": "my-app",
        "profiler": "memory:alloc_in_new_tlab_bytes:bytes:space:bytes"
      }
    ]
  }'
```

## Available Profiler Types

Perfana supports the following Java-based profiler types:

| Label | Value | What it measures |
|-------|-------|------------------|
| **process_cpu/cpu** | `process_cpu:cpu:nanoseconds:cpu:nanoseconds` | CPU time per function |
| **memory/alloc_in_new_tlab_bytes** | `memory:alloc_in_new_tlab_bytes:bytes:space:bytes` | Memory allocation in bytes |
| **memory/alloc_in_new_tlab_objects** | `memory:alloc_in_new_tlab_objects:count:space:bytes` | Memory allocation by object count |
| **mutex/contentions** | `mutex:contentions:count:mutex:count` | Mutex lock contention count |
| **mutex/delay** | `mutex:delay:nanoseconds:mutex:count` | Time spent waiting on mutex locks |
| **block/contentions** | `block:contentions:count:block:count` | Thread block contention count |
| **block/delay** | `block:delay:nanoseconds:block:count` | Time spent in blocked state |

## Step 3: View Profiling Data in Test Runs

Once configured, profiling data appears automatically on test run detail pages:

1. Open a **Test Run** for a system with Pyroscope configured
2. The **Pyroscope card** shows the configured applications and profiler types
3. Click to view the flamegraph for the test run's time window

### Comparing with a Baseline

Perfana can compare profiling data between two test runs to detect regressions:

1. On the test run detail page, expand the Pyroscope card
2. Select a **baseline test run** for comparison
3. Perfana generates a differential flamegraph showing:
   - **Regressions** — functions consuming more resources than the baseline
   - **Improvements** — functions consuming fewer resources
   - **New hotspots** — functions that didn't appear in the baseline
4. A summary table shows the top changes with percentage deltas

### Flamegraph Analysis via API

```bash
curl -X POST https://your-perfana/api/pyroscope/analyze-flamegraphs \
  -H "Authorization: Bearer <your-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "backendUrl": "http://pyroscope:4040",
    "application": "my-app",
    "profilerLabel": "process_cpu",
    "baselineStartTime": 1705312800000,
    "baselineEndTime": 1705316400000,
    "currentStartTime": 1705399200000,
    "currentEndTime": 1705402800000,
    "significanceThreshold": 100
  }'
```

The response includes a summary, top function changes, regressions, improvements, and a markdown table report.

## Standalone vs Grafana-Embedded Mode

| Mode | Standalone | Grafana-Embedded |
|------|-----------|------------------|
| **Pyroscope URL** | Direct Pyroscope UI (e.g. `http://pyroscope:4040`) | Grafana URL with Pyroscope datasource |
| **Backend API URL** | Same as Pyroscope URL or internal endpoint | Direct Pyroscope API for server-side queries |
| **Standalone toggle** | Enabled | Disabled |
| **URL format** | Uses Pyroscope native query params | Uses Grafana Explore with `explorationType=flame-graph` |

## Pyroscope Infrastructure Example

A typical `docker-compose.yml` setup:

```yaml
pyroscope:
  image: grafana/pyroscope:latest
  ports:
    - "4040:4040"
  volumes:
    - pyroscope-data:/data
```

In this setup:
- **Pyroscope URL**: `http://pyroscope:4040` (standalone) or `https://grafana.example.com` (embedded)
- **Backend API URL**: `http://pyroscope:4040`

## Troubleshooting

| Problem | Solution |
|---------|----------|
| **Test Connection fails** | Verify the Pyroscope URL is reachable from the Perfana server. For embedded mode, check the Backend API URL separately. |
| **No profiling data in test runs** | Ensure your application's Pyroscope agent is running and sending data. Verify the application name matches exactly. |
| **Flamegraph analysis returns empty** | Check that the Backend API URL is set and points to Pyroscope's HTTP API (not the Grafana URL). |
| **Wrong profiler type** | Use the `/pyroscope/profiler-types` endpoint to list available types, then match with your application's instrumentation. |
| **Comparison shows no changes** | Verify both test runs have profiling data for the same application and profiler type. Adjust the significance threshold if changes are small. |
