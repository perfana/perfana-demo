---
name: perfana-report
description: >
  Use this skill to analyse a Perfana performance test run and generate a comprehensive
  standardised performance test report written directly into Obsidian. Includes automatic
  cross-source root cause investigation when data sources (Tempo traces, Loki logs,
  Pyroscope flamegraphs, Dynatrace problems) are connected. Trigger when the user says things like "analyse test run",
  "generate a Perfana report", "write a performance test report", "create a report for run X",
  "analyse PerfanaWebshop-acc-loadTest-XXXXX", "report on the latest load test",
  "find root cause", "why did performance regress", or "investigate regression".
  Also trigger when the user asks to compare a run to a baseline or summarise test results.
  Requires Perfana MCP and Obsidian Local REST API.
context: fork
disable-model-invocation: true
---

# Perfana performance test report

Fetches all Perfana data for a test run, classifies regressions, derives hypotheses,
investigates root causes across connected data sources (traces, logs, flamegraphs, infrastructure),
and writes a standardised Markdown report to an Obsidian vault.

## Step 0 — MCP preflight check

Before doing anything else, verify which MCP servers are available. Use `ToolSearch` to
probe each server. This determines which investigation paths are open later.

### Perfana MCP (required)

Search for `mcp__perfana__get_recent_runs`.

- **Found** → Perfana MCP is configured. Continue.
- **Not found** → **Stop.** Tell the user:
  > "Perfana MCP is not configured. Add it with the command printed at the end of
  > `./init-demo.sh`, then restart Claude Code and retry."

### Grafana MCP (recommended)

Search for `mcp__grafana__list_datasources`.

- **Found** → Grafana MCP is configured. Unlocks:
  - Direct Pyroscope profile queries (`query_pyroscope`, `list_pyroscope_profile_types`)
  - Dashboard panel snapshots and raw metric queries
  - Loki log queries
  - Tempo TraceQL queries via `tempo_traceql-search` and related proxied tools
- **Not found** → Grafana MCP unavailable. Note the gap; continue with Perfana wrappers only.
  > "Grafana MCP not configured — Pyroscope profiles and direct dashboard queries will use
  > Perfana wrappers only. Run `claude mcp add grafana ...` (see init-demo.sh output) for
  > richer investigation."

### Tempo (via Grafana MCP proxied tools)

Tempo is accessed as a proxied tool through the Grafana MCP. The probe uses
`list_datasources` (already available if `grafanaMcpAvailable` is true) to discover
the Tempo datasource UID — which is required for all subsequent `tempo_*` tool calls.

If `grafanaMcpAvailable` is true, call:

```
grafana:list_datasources
```

Scan the results for a datasource with `type: "tempo"`.

- **Found** → Set `tempoMcpAvailable = true`. Store its `uid` as `tempoDatasourceUid`.
  Unlocks:
  - Custom TraceQL queries with arbitrary filters via `tempo_traceql-search`
  - Attribute introspection via `tempo_get-attribute-names`
  - Time-range searches not tied to a Perfana run window
  - Tag-based aggregations across many traces
- **Not found** → Tempo unavailable. Note the gap; Tempo queries will fall back to Perfana wrappers.
  > "Tempo datasource not found in Grafana — custom TraceQL queries unavailable. Verify
  > the Tempo datasource is configured in Grafana (http://localhost:3000)."

### Loki (via Grafana MCP proxied tools)

Loki is accessed as a proxied tool through the Grafana MCP, alongside Tempo.

If `grafanaMcpAvailable` is true, probe Loki availability in two steps:

**Step 1 — discover the Loki datasource UID** (required; `datasourceUid` is a mandatory parameter on all Loki tools):

```
grafana:list_datasources  { type: "loki" }
```

Store the first result's `uid` as `lokiDatasourceUid`. If the result is empty, Loki is not configured — skip log investigation.

**Step 2 — confirm Loki is queryable**:

```
grafana:list_loki_label_names  { datasourceUid: "<lokiDatasourceUid>" }
```

- **Succeeds** → Loki is reachable through Grafana. Unlocks:
  - LogQL queries against all services scoped to the test window
  - Error and exception log extraction with stack traces
  - Log volume analysis and pattern detection for regression pinpointing
  - Cross-correlation of log spikes with metric regressions and slow traces
- **Fails** → Loki unavailable. Note the gap; log investigation will be skipped.
  > "Loki is unreachable through Grafana MCP — log-based investigation unavailable. Verify
  > the Loki datasource is configured in Grafana (http://localhost:3000)."

Pass `lokiDatasourceUid` to every subsequent `grafana:query_loki_*` and `grafana:list_loki_*` call.

### Print preflight summary before proceeding

```
MCP preflight:
  Perfana : ✓ / ✗   (required — skip the rest if ✗)
  Grafana : ✓ / ✗   (Pyroscope profiles, dashboard panels, Tempo + Loki proxied tools)
  Tempo   : ✓ / ✗   (proxied via Grafana — custom TraceQL queries)
  Loki    : ✓ / ✗   (proxied via Grafana — log queries, error extraction, pattern detection)
```

Store the availability flags (`grafanaMcpAvailable`, `tempoMcpAvailable`, `lokiMcpAvailable`)
— they are referenced explicitly in Step 3.6 to decide which tool calls to make.
`tempoMcpAvailable` and `lokiMcpAvailable` are true only when Grafana MCP is available
AND the respective probe succeeds.

## Step 1 — Resolve inputs

Ask for `testRunId` if not provided. Accept optional `baselineRunId`.
If no baseline, call `perfana:get_recent_runs` and use the most recent run
where `is_control_group: true` for the same SUT / environment / workload.

## Step 2 — Choose output destination

Ask the user: **"Write the report to Obsidian or save as a local file?"**

- **Obsidian** → Read the API key from the vault config using the Filesystem MCP:
  ```
  Filesystem:read_text_file  {vaultRoot}/.obsidian/plugins/obsidian-local-rest-api/data.json
  ```
  Extract `$.apiKey`. See `references/obsidian-api.md` for endpoint details.
- **Local file** → The report will be written to `./reports/{testRunId}.md` in the current working directory.

## Step 3 — Fetch all Perfana data in parallel

Call these tools simultaneously (do not wait for one before starting the next):

```
perfana:get_test_run             { testRunId }
perfana:get_transaction_stats    { testRunId }
perfana:get_check_results        { testRunId }
perfana:get_adapt_results        { testRunId }
perfana:get_performance_rankings { testRunId, dimension: "slowest" }
perfana:get_performance_rankings { testRunId, dimension: "highest_impact" }
perfana:get_performance_rankings { testRunId, dimension: "highest_error_rate" }
perfana:get_error_analysis       { testRunId }
perfana:get_deep_links           { testRunId }
perfana:get_recent_runs          { systemUnderTest, testEnvironment, workload, limit: 5 }
```

If a baseline is available, also call in parallel:

```
perfana:compare_runs    { baselineRunId, testRunId }
perfana:get_config_diff { baselineRunId, testRunId }
```

For each entry in `get_error_analysis.topErrorsByTransaction`, call:

```
perfana:get_error_details { testRunId, transactionName, samplerName, url }
```

## Step 3.5 — Review pre-classified adapt data

The `get_adapt_results` tool returns **pre-processed** data — no manual parsing needed.
The response includes:

- `classifiedRegressions` — each regression already tagged with a classification
  (Computation kernel, Transaction latency, JVM memory / GC, Container resources, etc.)
  and a generated hypothesis string
- `byDashboard` — regressions grouped by dashboard with source type labels
  (Performance test, JVM monitoring, Infrastructure, Connection pool, etc.)
- `causalChains` — detected cross-source causal chains with confidence levels
  (e.g. "Compute regressions → CPU spike → GC pressure" = High confidence)
- `hypotheses` — deduplicated list of all hypotheses ready for investigation

From `get_check_results`: also list all **failed** SLO checks. Note the dashboard and metric.

Use the `hypotheses` list directly to drive targeted investigation in the next step.

## Step 3.6 — Discover connected sources and investigate

### System Under Test — source code context

The **PerfanaWebshop** application (the system exercised by all demo load tests) is an open-source
Spring Boot application hosted at:

> **https://github.com/perfana/afterburner**

**Whenever a flamegraph hotspot or slow trace names a specific method, fetch the source file and
read the implementation.** Do not skip this step — reading the code turns a hotspot observation
into an explanation of *why* that code causes the observed behaviour.

#### How to fetch source files

**Step 1 — discover the package structure** (do once per investigation):

```
WebFetch { url: "https://api.github.com/repos/perfana/afterburner/contents/src/main/java/nl/stokpop/afterburner" }
```

This returns a JSON directory listing. Identify the file that is most likely to contain the
hotspot method (e.g. `AfterburnerService.java`, `AfterburnerEngine.java`).

**Step 2 — fetch the relevant source file** using the raw URL:

```
WebFetch { url: "https://raw.githubusercontent.com/perfana/afterburner/main/src/main/java/nl/stokpop/afterburner/<FileName>.java" }
```

Read the method body. Look for:
- Loops or mathematical operations that explain CPU cost
- HTTP client calls that explain downstream latency
- `DataSource` / connection acquisition that explains pool exhaustion
- Configurable parameters (passed in via query string or Spring properties) that control severity

**Step 3 — quote the method in the report:**

```java
// AfterburnerService.java — doMatrixCalculation()
public double doMatrixCalculation(int matrixSize) {
    double[][] matrix = new double[matrixSize][matrixSize];
    // ... fills and multiplies matrix — O(n²) CPU cost
}
```

> Root cause confirmed: `matrix-calculation-count` config controls `matrixSize`. A larger value
> was active in this run, which explains the CPU regression.
> Source: https://github.com/perfana/afterburner/blob/main/src/main/java/nl/stokpop/afterburner/AfterburnerService.java

If the file is not found at the expected path, search for it:

```
WebFetch { url: "https://api.github.com/search/code?q=repo:perfana/afterburner+<methodName>" }
```

---

First, discover what Perfana-side data sources are available:

```
perfana:list_connected_sources  { testRunId }
```

This returns `{grafana, tempo, pyroscope, dynatrace}` with `available: true/false` for each.

Then, read `references/investigation-playbook.md` for the full mapping of hypothesis types
to investigation tool calls, including when to use direct `grafana:*` tools (Loki, Tempo, Pyroscope).

For each hypothesis from Step 3.5, call the tools prescribed by the playbook —
but **only if the required source is available**. Run calls for independent hypotheses
in parallel.

**Available MCP servers for investigation (use all that are available):**

| Server | Role | When to use |
|---|---|---|
| `perfana:*` | Primary wrappers | Always — correlated to test run time window automatically |
| `grafana:*` | Direct queries + proxied Tempo + proxied Loki | **Always if `grafanaMcpAvailable`** — Pyroscope profiles, dashboard panels, Tempo TraceQL, Loki log queries |

### Proactive Grafana MCP use (when `grafanaMcpAvailable`)

Do not wait for Perfana wrappers to fail. Whenever Pyroscope, dashboard, or log data is
relevant to a hypothesis, call the Grafana MCP in parallel with the Perfana wrapper:

**Pyroscope — run in parallel with `perfana:get_hotspots` / `get_flamegraph`:**
```
grafana:list_pyroscope_profile_types  { }
grafana:query_pyroscope               { profileTypeId: "process_cpu:cpu:nanoseconds:cpu:nanoseconds",
                                        serviceName: affectedService,
                                        from: runStart, to: runEnd }
```
Also query the memory profile type if GC regressions are detected:
```
grafana:query_pyroscope               { profileTypeId: "memory:alloc_in_new_tlab_bytes:bytes:space:bytes",
                                        serviceName: affectedService,
                                        from: runStart, to: runEnd }
```
The Grafana MCP returns richer flamegraph data than the Perfana wrapper and supports
direct profile-type selection. Compare results: if Perfana and Grafana flamegraphs agree
on a hotspot method, that is corroborating evidence.

**Dashboard panels — run in parallel with `perfana:get_grafana_dashboard_snapshot`:**
```
grafana:get_dashboard_panel_queries   { dashboardUid }   ← discover panel IDs first
grafana:get_panel_image               { dashboardUid, panelId,
                                        from: runStart, to: runEnd }
```
Use dashboard UIDs from `get_adapt_results` regression entries (the `dashboard_uid` field).

### Proactive Loki use via Grafana MCP (when `lokiMcpAvailable`)

Do not wait for error evidence from Perfana. For every affected service, run log queries
in parallel with the Perfana and Pyroscope calls.

**Error and exception extraction — run in parallel with `perfana:get_error_analysis`:**
```
grafana:list_loki_label_names  { datasourceUid: "<lokiDatasourceUid>" }   ← confirm `service_name` label exists; do once
grafana:query_loki_logs  { datasourceUid: "<lokiDatasourceUid>",
                           logql: "{service_name=\"<affectedService>\"} |= \"ERROR\"",
                           startRfc3339: runStart, endRfc3339: runEnd, limit: 100 }
grafana:query_loki_logs  { datasourceUid: "<lokiDatasourceUid>",
                           logql: "{service_name=\"<affectedService>\"} |= \"Exception\"",
                           startRfc3339: runStart, endRfc3339: runEnd, limit: 50 }
```

**What to look for in error logs:**

| Log pattern | Interpretation |
|---|---|
| `Connection refused` / `SocketTimeoutException` | Downstream connectivity failure |
| `HikariPool` / `Connection is not available` | Connection pool exhaustion — corroborates Hikari metric regressions |
| `OutOfMemoryError` / `GC overhead limit exceeded` | JVM memory pressure — corroborates GC regressions |
| `TimeoutException` / `ReadTimeoutException` | Slow downstream — the error is in a dependency, not this service |
| `IllegalArgumentException` / `NullPointerException` | Application bug; check if new in this release |
| `CircuitBreakerOpenException` | Upstream saw too many failures and opened the circuit |

**Log volume spike detection — run alongside error queries:**
```
grafana:query_loki_stats  { datasourceUid: "<lokiDatasourceUid>",
                            query: "{service_name=\"<affectedService>\"} |= \"ERROR\"",
                            from: runStart, to: runEnd }
```
A log-volume spike that starts at the same time as the metric regression from Adapt is
strong corroborating evidence. Compare the spike shape against the Adapt timeline.

**Pattern discovery — when you don't know what to look for:**
```
grafana:query_loki_patterns  { datasourceUid: "<lokiDatasourceUid>",
                               query: "{service_name=\"<affectedService>\"}",
                               from: runStart, to: runEnd }
```
Returns top log patterns ranked by frequency. Patterns that are new or absent in the
baseline run often point directly to the root cause without needing to read raw lines.

**GC / JVM log investigation — when JVM memory or GC regression is detected:**
```
grafana:query_loki_logs  { datasourceUid: "<lokiDatasourceUid>",
                           logql: "{service_name=\"<affectedService>\"} |= \"GC\"",
                           startRfc3339: runStart, endRfc3339: runEnd, limit: 50 }
grafana:query_loki_logs  { datasourceUid: "<lokiDatasourceUid>",
                           logql: "{service_name=\"<affectedService>\"} |= \"safepoint\"",
                           startRfc3339: runStart, endRfc3339: runEnd, limit: 30 }
```

**Connection pool log investigation — when Hikari regression is detected:**
```
grafana:query_loki_logs  { datasourceUid: "<lokiDatasourceUid>",
                           logql: "{service_name=\"<affectedService>\"} |= \"HikariPool\"",
                           startRfc3339: runStart, endRfc3339: runEnd, limit: 50 }
```

### Proactive Tempo use via Grafana MCP (when `tempoMcpAvailable`)

Do not wait for Perfana trace tools to fail. Run a targeted TraceQL query in parallel
with `perfana:get_slow_traces` for each regressed transaction:

```
grafana:tempo_traceql-search  { query: "{ .perfana-request-name = \"<Scenario>|<Transaction>|<Sampler>\"
                                           && duration > <expectedDuration> }",
                                  datasourceUid: tempoDatasourceUid,
                                  start: runStart, end: runEnd }
```

For error-rate hypotheses, also query error spans directly:
```
grafana:tempo_traceql-search  { query: "{ status = error
                                           && resource.service.name = \"<affectedService>\" }",
                                  datasourceUid: tempoDatasourceUid,
                                  start: runStart, end: runEnd }
```

These proxied Tempo tools allow arbitrary TraceQL filters not possible through Perfana wrappers.
Use trace IDs from results to call `perfana:get_trace_detail` for full span breakdown.

### Trace diff (baseline vs current)

When Tempo is available **and** a baseline run exists, perform a trace comparison:

1. **Broad trace diff** — fetch the top 10 slowest traces for both runs:
   ```
   get_slow_traces { testRunId: currentRunId, limit: 10 }
   get_slow_traces { testRunId: baselineRunId, limit: 10 }
   ```
   Compare: max duration (excluding synthetic timers like `enable-traffic-light`),
   median duration, and whether new trace operation types appeared.

2. **Per-transaction trace diff** — for the top 3 most regressed transactions
   (from `get_adapt_results`, sorted by `change_pct` desc), fetch traces for
   both runs with scenario/transaction/service filtering:
   ```
   get_slow_traces { testRunId: currentRunId, scenario, transaction, service, limit: 5 }
   get_slow_traces { testRunId: baselineRunId, scenario, transaction, service, limit: 5 }
   ```
   Compare: are there new operation types in the current run that don't appear
   in the baseline? Did trace durations increase? Did the span composition change
   (e.g., I/O-bound → CPU-bound)?

3. **Span-level drill-down** — for traces that show new or significantly slower
   operations, call `get_trace_detail` on both the current and baseline traces
   to compare span breakdowns:
   ```
   get_trace_detail { testRunId: currentRunId, traceId }
   get_trace_detail { testRunId: baselineRunId, traceId }
   ```
   Look for: new spans not present in baseline, span duration shifts,
   span attributes (e.g., `matrix-size`, `batch-count`) that reveal
   parameterisation changes.

The trace diff is one of the strongest forms of evidence — it shows exactly
what changed at the request level between runs. Upgrade the Tempo evidence
from "Partial" to "Yes" in the evidence chain when the trace diff confirms
the hypothesis.

### Log diff (baseline vs current)

When `lokiMcpAvailable` and a baseline run exists, compare log patterns across runs —
logs often reveal the root cause faster than metrics or traces.

1. **Error volume diff** — compare ERROR log counts between runs:
   ```
   grafana:query_loki_stats  { datasourceUid: "<lokiDatasourceUid>",
                               query: "{service_name=\"<service>\"} |= \"ERROR\"",
                               from: currentRunStart, to: currentRunEnd }
   grafana:query_loki_stats  { datasourceUid: "<lokiDatasourceUid>",
                               query: "{service_name=\"<service>\"} |= \"ERROR\"",
                               from: baselineRunStart, to: baselineRunEnd }
   ```
   A significant increase in error volume directly corroborates error-rate regressions from Adapt.

2. **New error patterns** — patterns present in current but absent in baseline are the
   strongest log-based evidence of a regression:
   ```
   grafana:query_loki_patterns  { datasourceUid: "<lokiDatasourceUid>",
                                  query: "{service_name=\"<service>\"}",
                                  from: currentRunStart, to: currentRunEnd }
   grafana:query_loki_patterns  { datasourceUid: "<lokiDatasourceUid>",
                                  query: "{service_name=\"<service>\"}",
                                  from: baselineRunStart, to: baselineRunEnd }
   ```
   Cross-reference the two pattern lists. Any pattern in current but not baseline is a lead.

3. **Exception type diff** — extract exception class names from both runs to spot new failures:
   ```
   grafana:query_loki_logs  { datasourceUid: "<lokiDatasourceUid>",
                              logql: "{service_name=\"<service>\"} |= \"Exception\"",
                              startRfc3339: currentRunStart, endRfc3339: currentRunEnd, limit: 50 }
   grafana:query_loki_logs  { datasourceUid: "<lokiDatasourceUid>",
                              logql: "{service_name=\"<service>\"} |= \"Exception\"",
                              startRfc3339: baselineRunStart, endRfc3339: baselineRunEnd, limit: 50 }
   ```
   A new exception type in the current run that doesn't appear in baseline points to
   the failing code path. Upgrade log evidence to "Strong" when a new exception type
   also matches a service seen in slow traces.

If a tool call returns an error or empty data:
- Log which source was unavailable and why
- Skip that investigation branch
- Note the gap: "Loki logs were not available — log-based analysis was skipped"
- **Never abort the entire analysis because one source failed**

If `list_connected_sources` shows no sources available at all, skip to Step 4 and note:
"No external data sources connected — investigation based on Perfana metrics only."

## Step 3.7 — Correlate evidence across sources

Cross-reference the investigation results to strengthen or weaken each hypothesis.

**Correlation patterns to check:**

1. **Adapt cross-source causal chain:** Group regressions from `get_adapt_results` by their
   `dashboard` field — each dashboard represents a different data source (performance test
   metrics = JMeter/Gatling, JVM memory = Grafana JVM dashboard, Docker container = Grafana
   infra, Hikari = Grafana connection pool, etc.). Look for causal chains across sources:
   - Compute subrequest regressions (perf test) → CPU spike (Docker container) → GC pressure (JVM) → **High confidence**
   - Latency regression (perf test) → connection pool saturation (Hikari) → **High confidence**
   - Error rate spike (perf test) + CPU spike (Docker) + Dynatrace problem → **High confidence**
   This correlation is available from Adapt data alone — no traces or flamegraphs needed.

2. **Trace ↔ Flamegraph:** Do the slowest traces point to the same service/method that
   appears as a hotspot in the flamegraph? If yes → **High confidence**.

3. **Metric ↔ Trace:** Does the timing of the metric regression (from Adapt) match the
   duration of slow traces? If traces show 2s calls and the metric regressed by 2s → **High confidence**.

4. **Dynatrace ↔ Metric:** Did a Dynatrace problem start at the same time as the regression?
   If a "CPU saturation" problem coincides with a CPU metric regression → **High confidence**.

5. **Config ↔ Everything:** Did a config change (from `get_config_diff`) coincide with the
   regression? If thread pool size was halved and connection pool metrics regressed → **High confidence**.

6. **Flamegraph ↔ GC:** Does the flamegraph show GC-related methods (containing `gc`, `G1`,
   `safepoint`, `cleanup`) as hotspots? If yes and JVM memory metrics regressed → **High confidence**.

7. **Logs ↔ Metrics:** Do ERROR log spikes (from `query_loki_stats`) start at the same
   time as metric regressions from Adapt? Overlapping timelines across independent sources → **High confidence**.

8. **Logs ↔ Traces:** Does the exception type extracted from Loki match the service or
   operation visible in slow traces? Agreement between logs and traces → **High confidence**.

9. **Logs ↔ Flamegraph:** Do GC log messages (`GC`, `safepoint`, `G1`) appear during the
   same window as GC hotspots in the flamegraph? If yes and JVM memory metrics also regressed → **High confidence**.

10. **New log pattern ↔ Everything:** A log pattern present in the current run but absent
    in the baseline is among the strongest single signals — it indicates something new happened.
    Treat it as **High confidence** for any hypothesis it supports.

**Assign confidence to each hypothesis:**

| Level | Criteria |
|---|---|
| **High** | Corroborating evidence from 2+ independent sources |
| **Medium** | Evidence from 1 source with plausible mechanism |
| **Low** | Hypothesis consistent with symptoms but no direct evidence |

Pick the **single most likely root cause** — the hypothesis with the highest confidence
and most corroborating evidence. The report should be opinionated, not a list of "could be"s.

## Step 4 — Classify regressions and derive hypotheses (enhanced with investigation)

Read `references/classification-rules.md` for the full classification table and
hypothesis guide. Apply to all regressions and differences from `get_adapt_results`.

Enrich each hypothesis with the investigation evidence from Steps 3.6–3.7:
- Attach the confidence level (High/Medium/Low) from the correlation step
- Include specific evidence references (e.g., "trace abc123 shows 2.1s in OrderService.process()")
- Note which sources contributed evidence and which were unavailable

Compute derived metrics:
- **p99 tail overshoot** = `p99_response_time − active_threshold` (from `get_transaction_stats`)
- **Flaky error flag** = true if all error URLs match `/flaky`

## Step 5 — Build the report

Read `references/report-template.md` and fill every section from the fetched data.
Write `_No data available_` for any section with no data — never leave placeholders.

## Step 6 — Write report to chosen destination

### If Obsidian was chosen:

```bash
curl -s -X PUT \
  "http://localhost:27123/vault/Performance%20Reports/${TEST_RUN_ID}.md" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: text/markdown" \
  --data-binary "${REPORT_MARKDOWN}"
```

Expect HTTP 200 or 204. Confirm to the user:
> "Report written to Obsidian at `Performance Reports/{testRunId}.md`"

### If local file was chosen:

Write the report to `./reports/{testRunId}.md` using the Write tool.
Create the `reports/` directory if it doesn't exist.
Confirm to the user:
> "Report written to `reports/{testRunId}.md`"

## Error handling

| Situation | Action |
|---|---|
| `get_adapt_results` parse error | Retry once; fall back to `consolidated_result.adaptTestRunOK` from `get_test_run`; note in report |
| `get_config_diff` no result | Write "Config diff unavailable" in report; continue |
| `get_transaction_stats` no result | Use Apdex from `get_check_results`; omit p99 column |
| No `is_control_group` run found | Use most recent completed run as baseline; note the assumption |
| `list_connected_sources` error | Skip Perfana-sourced investigation; still use Grafana/Tempo MCPs if available |
| `get_slow_traces` empty result | Escalate to Grafana-proxied Tempo TraceQL query if `tempoMcpAvailable`; else write "No slow traces found" |
| `get_error_traces` empty result | Escalate to Grafana-proxied Tempo `{ status = error }` query if `tempoMcpAvailable`; else write "No error traces found" |
| `get_flamegraph` error (service not found) | Escalate to `grafana:list_pyroscope_profile_types` + `grafana:query_pyroscope` if `grafanaMcpAvailable`; else write "Pyroscope unavailable" |
| `get_hotspots` empty result | Escalate to `grafana:query_pyroscope` if `grafanaMcpAvailable`; else write "No CPU hotspots detected" |
| `get_dynatrace_problems` empty result | Write "No Dynatrace problems detected during test window" — this is a positive signal |
| `get_trace_detail` error | Skip that trace; continue with remaining traces |
| `get_grafana_dashboard_snapshot` error | Escalate to `grafana:search_dashboards` + `grafana:get_panel_image`; if those fail too, note gap |
| Grafana MCP tool error | Log which tool failed; continue with Perfana wrappers; note "Grafana MCP returned error for X" |
| Grafana-proxied Tempo tool error | Log which query failed; continue with Perfana trace wrappers; note "Tempo (via Grafana MCP) returned error for X" |
| `grafana:query_pyroscope` no data | Write "No Pyroscope data for service X in this run window"; check `list_pyroscope_profile_types` to confirm service name |
| Loki probe fails (preflight) | Set `lokiMcpAvailable = false`; skip all Loki queries; note "Loki unreachable via Grafana MCP — log investigation skipped" |
| `grafana:query_loki_logs` empty | Try `grafana:list_loki_label_values { datasourceUid: "<lokiDatasourceUid>", labelName: "service_name" }` to confirm the label value; write "No logs found for service X" |
| `grafana:query_loki_patterns` error | Fall back to plain `query_loki_logs`; note "Loki pattern detection unavailable" |
| `grafana:query_loki_stats` error | Skip log volume diff; continue with raw log lines from `query_loki_logs` |
| No sources connected at all and no Grafana/Tempo/Loki MCPs | Skip Steps 3.6–3.7; write "No external data sources connected" in report |
| Obsidian 401 | Re-read `data.json`; key may have rotated |
| Obsidian connection refused | Suggest local file output instead; Obsidian may not be running |
| Path spaces | URL-encode spaces as `%20` in the PUT path |
