# Investigation playbook

## System Under Test — source reference

All demo load tests target the **PerfanaWebshop** application, built on the open-source
[Afterburner](https://github.com/perfana/afterburner) Spring Boot framework.

Whenever a flamegraph hotspot or slow trace names a specific method, **fetch and read the
source file** using `WebFetch` — do not skip this step:

```
# 1. Discover package structure
WebFetch { url: "https://api.github.com/repos/perfana/afterburner/contents/src/main/java/nl/stokpop/afterburner" }

# 2. Fetch the relevant file (replace <FileName> with actual file from step 1)
WebFetch { url: "https://raw.githubusercontent.com/perfana/afterburner/main/src/main/java/nl/stokpop/afterburner/<FileName>.java" }

# 3. If path unknown, search by method name
WebFetch { url: "https://api.github.com/search/code?q=repo:perfana/afterburner+<methodName>" }
```

Common configurable behaviours and the source methods they invoke:

| Endpoint / config knob | What it does | Source method hint |
|---|---|---|
| `cpu-burn-milliseconds` | Burns CPU in a tight loop | `AfterburnerService#burnCpu` |
| `backend-calls` | Makes N HTTP calls to a downstream service | `AfterburnerService#doSlowBackendCall` |
| `connection-pool-delay` | Holds a DB connection for X ms, exhausting the pool | `AfterburnerService#doConnectionPoolDelay` |
| `matrix-calculation-count` | Matrix multiplication — pure CPU computation | `AfterburnerService#doMatrixCalculation` |

When reporting a root cause, link directly to the relevant source file and name the config
knob so the reader understands how to reproduce or tune the behaviour.

Maps regression classifications (from `classification-rules.md`) to targeted MCP tool
calls. For each hypothesis type, this table prescribes which tools to call and what to
look for in the results.

**MCP availability flags** (set in Step 0 of the skill):
- `grafanaMcpAvailable` — `mcp__grafana__*` tools are loaded
- `tempoMcpAvailable` — Tempo is reachable via Grafana MCP (probe succeeded)
- `lokiMcpAvailable` — Loki is reachable via Grafana MCP (probe succeeded)

## Hypothesis → Investigation mapping

Each row lists the Perfana wrapper **and** the direct MCP enrichment to run in parallel
when the corresponding MCP server is available.

| Classification | Perfana tool | Grafana MCP — Traces/Profiles (if `tempoMcpAvailable` / `grafanaMcpAvailable`) | Grafana MCP — Logs (if `lokiMcpAvailable`) | What to look for |
|---|---|---|---|---|
| **Transaction latency** | `get_slow_traces { testRunId, service, limit:10 }` | `grafana:find_slow_requests` for the service; TraceQL: `{ .perfana-request-name =~ "<Transaction>.*" && duration > Xs }` | `query_loki_logs` for slow-request log lines from the service | Which downstream span dominates? Matching slow log entries? |
| **Transaction latency** | `get_trace_detail { testRunId, traceId }` (top 3) | `grafana:get_panel_image` for response-time panel | — | Full span breakdown on critical path |
| **Request latency** | `get_slow_traces { testRunId, service, limit:10 }` | `grafana:find_slow_requests`; TraceQL: `{ resource.service.name = "<service>" && duration > Xs }` | `query_loki_logs` for `WARN`/`ERROR` lines; `query_loki_stats` for volume spike | Same as transaction latency |
| **Computation kernel** | `get_hotspots { testRunId, service, limit:20 }` | `grafana:query_pyroscope { profileTypeId: "process_cpu:cpu:nanoseconds:cpu:nanoseconds", serviceName }` | `query_loki_patterns` to surface unexpected compute-heavy log patterns | Compute methods in top hotspots? |
| **Computation kernel** | `get_flamegraph { testRunId, service, detailLevel:"full" }` | `grafana:query_pyroscope` (richer stack data) | — | Does flamegraph show compute method dominating CPU? |
| **JVM memory / GC** | `get_hotspots { testRunId, service }` | `grafana:query_pyroscope { profileTypeId: "memory:alloc_in_new_tlab_bytes:bytes:space:bytes", serviceName }` | `query_loki_logs { query: "{service_name=\"<service>\"} \|= \"GC\"" }` — GC pause messages, OOM errors | GC methods in flamegraph; `GC overhead`, `OutOfMemoryError` in logs |
| **JVM memory / GC** | `get_grafana_dashboard_snapshot { testRunId, dashboard: JVM_DASHBOARD }` | `grafana:get_panel_image` for heap/GC panels | `query_loki_logs { query: "{service_name=\"<service>\"} \|= \"safepoint\"" }` | Heap usage, GC pause time; safepoint log entries |
| **JVM CPU / threads** | `get_flamegraph { testRunId, service, detailLevel:"summary" }` | `grafana:query_pyroscope { profileTypeId: "process_cpu:cpu:nanoseconds:cpu:nanoseconds" }` | `query_loki_logs` for thread-pool or executor log messages | CPU profile — which methods are hot? Thread pool exhaustion logs? |
| **Container resources** | `get_grafana_dashboard_snapshot { testRunId, dashboard: CONTAINER_DASHBOARD }` | `grafana:get_panel_image` for CPU and memory panels | `query_loki_logs` for OOM kill or resource limit messages | CPU throttling, memory limits, OOM events |
| **DB connection pool** | `get_grafana_dashboard_snapshot { testRunId, dashboard: HIKARI_DASHBOARD }` | `grafana:get_panel_image` for active-connections panel; TraceQL: `{ span.db.system != "" && duration > 500ms }` | `query_loki_logs { query: "{service_name=\"<service>\"} \|= \"HikariPool\"" }` — connection wait/timeout messages | Active connections at max; `Connection is not available` in logs |
| **Error rates** | `get_error_traces { testRunId, service, limit:10 }` | TraceQL: `{ status = error && resource.service.name = "<service>" }` | `query_loki_logs { query: "{service_name=\"<service>\"} \|= \"ERROR\"", limit:100 }` + `query_loki_stats` for volume + `query_loki_patterns` for new patterns | Timeouts? 5xx from downstream? New exception types in logs? |
| **Error rates** | `get_dynatrace_problems { testRunId }` | — | `query_loki_logs { query: "{service_name=\"<service>\"} \|= \"Exception\"", limit:50 }` | Dynatrace problem + matching exception in logs = High confidence |
| **Throughput drops** | `get_grafana_dashboard_snapshot { testRunId, dashboard: HTTP_DASHBOARD }` | `grafana:find_slow_requests` — did request rate change?; TraceQL: count traces per minute | `query_loki_stats` for request log volume over time — did log rate drop at same time? | Request rate over time — sudden or gradual drop? |
| **Infrastructure** | `get_dynatrace_problems { testRunId }` | `grafana:get_panel_image` for infra panels | `query_loki_logs` for host-level errors, disk I/O, network errors | Host CPU saturation, disk I/O, network issues |

## Dashboard name resolution

Dashboard names in the table above are placeholders. To find the actual name for a run:
1. Use the `dashboard` field from `get_adapt_results` regression entries — use it verbatim.
2. If it doesn't match, call `get_available_metrics { testRunId }` to list all dashboards.
3. For Grafana MCP panel calls, use `dashboard_uid` from the regression entry or search
   with `grafana:search_dashboards { query: "<dashboardLabel>" }`.

## Investigation order

1. **Always call first:** `list_connected_sources` — determines Perfana-side availability.
   Combined with Step 0 flags, you now know all four possible sources.

2. **Parallel batch 1 (broad):** For each affected service from Step 3.5, fire in parallel:
   - `perfana:get_slow_traces` for current run (if Tempo connected in Perfana)
   - `perfana:get_slow_traces` for baseline run (if baseline exists)
   - `perfana:get_hotspots` (if Pyroscope connected in Perfana)
   - `perfana:get_dynatrace_problems` (if Dynatrace connected)
   - `grafana:find_slow_requests` (if `tempoMcpAvailable`) — broad trace overview via Grafana
   - `grafana:query_pyroscope` for CPU profile (if `grafanaMcpAvailable`) — in parallel with `get_hotspots`
   - Tempo TraceQL for affected service (if `tempoMcpAvailable`) — broad slow-span query
   - `grafana:query_loki_logs` for ERROR lines per affected service (if `lokiMcpAvailable`)
   - `grafana:query_loki_stats` for error log volume (if `lokiMcpAvailable`) — detect spikes
   - `grafana:query_loki_patterns` per affected service (if `lokiMcpAvailable`) — surface new patterns

3. **Parallel batch 2 (targeted, after batch 1 results):**
   - Per-transaction trace diff: `get_slow_traces` with scenario/transaction/service
     for the top 3 regressed transactions, for **both** current and baseline runs
   - `get_trace_detail` for interesting traces (new operation types, biggest duration increase)
   - `get_flamegraph` if hotspots point to a specific method
   - `grafana:query_pyroscope` with memory profile type if GC regression detected
   - `grafana:get_panel_image` for dashboards mentioned in regressions (renders actual chart)
   - Tempo TraceQL per-transaction queries (if `tempoMcpAvailable`)
   - `grafana:query_loki_logs` targeted by hypothesis: `HikariPool` for pool, `GC`/`safepoint` for JVM,
     `Exception` for error-rate — run for current run **and** baseline run for diff
   - `grafana:query_loki_patterns` for baseline run (if `lokiMcpAvailable`) — compare against current patterns

4. **Skip if source unavailable.** Note the gap in the report but never abort.

## Trace diff methodology

When both a current and baseline run are available, the trace diff is a critical
investigation step. It reveals **what changed at the request level** between runs.

### What to compare

| Dimension | How to compare | What it reveals |
|---|---|---|
| **Max duration** | Exclude synthetic timers (e.g., `enable-traffic-light`), compare max of remaining traces | Overall latency ceiling shift |
| **New operation types** | List root operations in current that don't appear in baseline top traces | New code paths introduced by the release |
| **Span composition** | Compare `get_trace_detail` spans side-by-side | Whether the bottleneck shifted (e.g., I/O → CPU) |
| **Span attributes** | Check for parameterisation attributes (e.g., `matrix-size`, `batch-count`, `query-complexity`) | Whether the same operation runs with different inputs |
| **Tail distribution** | Compare the 4th–10th slowest traces | Whether the regression is uniform or concentrated |

### Interpreting trace diffs

| Pattern | Interpretation | Confidence |
|---|---|---|
| New span type dominates current traces, absent in baseline | Code change introduced new work on the request path | **High** |
| Same span type, but duration increased significantly | Existing operation became slower (algorithm change, contention) | **High** |
| Same spans, same durations, but more spans per trace | Fan-out or retry increase | **Medium** |
| Different span types dominate, but similar durations | Workload shift, not necessarily a regression | **Low** |

## Evidence quality assessment

When evaluating evidence from each source:

| Source | Strong evidence | Weak evidence |
|---|---|---|
| **Traces** | Slow span in exact service/method matching regression | Slow trace in unrelated service |
| **Flamegraph** | Hotspot method matches regressed metric name | Generic framework methods dominating (e.g., `Thread.run`) |
| **Dashboard snapshot** | Metric value changed significantly vs recent runs | Metric within normal range |
| **Dynatrace problems** | Problem time window overlaps test run exactly | Problem started hours before test |

## When to drill deeper

Call `get_trace_detail` (expensive — returns all spans) only when:
- The slow trace's root service matches a regressed service from Adapt
- The trace duration is >2x the expected response time
- You need to identify which specific downstream call is the bottleneck

Call `get_flamegraph` with `detailLevel: "full"` only when:
- `get_hotspots` shows a suspicious method in the top 5
- The hypothesis involves CPU-bound computation or GC pressure
- `detailLevel: "summary"` (top 50 stacks) wasn't enough to confirm

## Grafana MCP — proactive use and fallback

Direct Grafana MCP calls (Tempo, Loki, Pyroscope — all proxied) are **not just fallbacks**
— they are called in parallel with Perfana wrappers when available (see Investigation order).
This section documents additional use cases and the fallback escalation path.

### Additional Pyroscope / Tempo use cases

| Situation | Tool | Notes |
|---|---|---|
| Discover available Pyroscope services and profile types | `grafana:list_pyroscope_profile_types` | Run before querying Pyroscope — use exact profile type IDs returned |
| Compare CPU profiles: baseline vs current (diff view) | `grafana:query_pyroscope` with two time windows | Strongest form of flamegraph evidence |
| Memory allocation profile (GC regression) | `grafana:query_pyroscope { profileTypeId: "memory:alloc_in_new_tlab_bytes:bytes:space:bytes" }` | Reveals allocation hotspots |
| Render a dashboard panel as an image | `grafana:get_panel_image { dashboardUid, panelId, from, to }` | Attach to report as visual evidence |
| Search for a dashboard by name | `grafana:search_dashboards { query: "<label>" }` | Get the UID needed for panel calls |
| Find slow traces for a specific endpoint (Tempo) | `grafana:find_slow_requests` with TraceQL `{ .http.route = "/api/products" && duration > 2s }` | More precise than `get_slow_traces` which filters by service |
| Find error spans with status codes (Tempo) | TraceQL: `{ status = error && .http.status_code = 500 }` | Correlates with `get_error_analysis` results |
| Traces from a specific perfana-request-name (Tempo) | TraceQL: `{ .perfana-request-name = "Checkout\|T04_Payment\|auth" }` | Precise per-sampler trace filtering |
| Bypass Perfana time-window if `get_slow_traces` is empty | Use explicit `start`/`end` from `get_test_run` metadata | `get_test_run` returns `start_time` and `end_time` |

### Loki log investigation use cases (when `lokiMcpAvailable`)

| Situation | Tool call | Notes |
|---|---|---|
| Confirm available service labels before querying | `grafana:list_loki_label_values { labelName: "service_name" }` | Do once; use exact values in subsequent queries |
| Exception stack traces for error-rate hypothesis | `grafana:query_loki_logs { query: "{service_name=\"<svc>\"} \|= \"Exception\"" }` | Links error-rate regressions to specific exception types |
| Log volume over time — detect spikes | `grafana:query_loki_stats { query: "{service_name=\"<svc>\"} \|= \"ERROR\"", from, to }` | Compare spike shape vs Adapt regression timeline |
| New vs baseline log pattern diff | `grafana:query_loki_patterns { query: "{service_name=\"<svc>\"}", from, to }` | Run for both current and baseline time windows; diff the results |
| GC / JVM pressure investigation | `grafana:query_loki_logs { query: "{service_name=\"<svc>\"} \|= \"GC\"" }` | Look for `GC overhead limit exceeded`, long pause times |
| Connection pool exhaustion | `grafana:query_loki_logs { query: "{service_name=\"<svc>\"} \|= \"HikariPool\"" }` | `Connection is not available, request timed out` messages confirm pool saturation |
| Connectivity / timeout failures | `grafana:query_loki_logs { query: "{service_name=\"<svc>\"} \|= \"Connection refused\"" }` | Downstream unavailability visible in logs before traces |
| Circuit breaker activity | `grafana:query_loki_logs { query: "{service_name=\"<svc>\"} \|= \"CircuitBreaker\"" }` | Open circuit = downstream is failing repeatedly |
| Throughput drop — request log volume | `grafana:query_loki_stats { query: "{service_name=\"<svc>\"}" , from, to }` | Did the number of log lines drop at the same time as throughput? |
| Infrastructure / host errors | `grafana:query_loki_logs { query: "{job=\"<hostJob>\"} \|= \"error\"" }` | Disk, network, kernel errors on the host |

### Fallback escalation

When a Perfana wrapper fails or returns empty, escalate to direct Grafana MCP calls:

```
perfana:get_slow_traces      empty/error? → grafana:find_slow_requests (Tempo via Grafana)
perfana:get_trace_detail     error?       → use trace ID from Tempo result in get_trace_detail
perfana:get_hotspots         error?       → grafana:list_pyroscope_profile_types
                                            then grafana:query_pyroscope
perfana:get_flamegraph       error?       → grafana:query_pyroscope (same service, cpu profile)
perfana:get_error_analysis   sparse?      → grafana:query_loki_logs for ERROR/Exception lines
perfana:get_grafana_dashboard_snapshot
                             error?       → grafana:search_dashboards { query }
                                            then grafana:get_dashboard_panel_queries { dashboardUid }
                                            then grafana:get_panel_image for relevant panels
```

Use trace IDs obtained from Tempo (via Grafana) results in `perfana:get_trace_detail` calls —
Perfana's span-breakdown tool works with any valid trace ID.
