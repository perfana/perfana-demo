# Classification rules and hypothesis guide

## Classification table

Use `dashboard`, `panel`, and `metric_name` fields from each Adapt result entry:

| Classification | Match condition |
|---|---|
| **Computation kernel** | `metric_name` ends with `_compute`, `_processing`, `_ranking`, `_engine`, `_hash`, `_generate`; or URL contains `/cpu/` |
| **Transaction latency** | `panel` contains `"Transaction RT"` or `"Transaction Apdex"` |
| **Request latency** | `panel` contains `"Request RT"` or `"Request Latency"` |
| **JVM memory / GC** | `dashboard` contains `"JVM memory"` or `"G1GC"` |
| **JVM CPU / threads** | `dashboard` contains `"JVM"` AND `panel` contains `"CPU"` or `"Threads"` |
| **Container resources** | `dashboard` contains `"Docker container"` |
| **DB connection pool** | `dashboard` contains `"Hikari"` or `"connection pool"` |
| **Error rates** | `panel` contains `"Error Rate"` or `"Error Count"` |
| **Throughput** | `panel` contains `"Throughput"` |
| **Improvements** | `conclusion == "improvement"` |

## Hypothesis guide

| Classification | Hypothesis pattern |
|---|---|
| **Computation kernel** | The code change introduced CPU-bound work on the request thread. Sub-requests with `_compute`/`_processing` in their names are the direct source. Name the top `change_pct` offenders. |
| **Transaction latency** | Downstream consequence of slow compute sub-requests. The transaction chains multiple compute calls — as each slows, the total exceeds the Apdex threshold. |
| **JVM GC pressure** | High old-gen promotion rate (`promoted` metric with `change_pct > 500%`) combined with new major GC events = algorithm creating long-lived intermediate objects that survive minor GC. |
| **JVM CPU / threads** | The algorithm is CPU-bound, not I/O-bound. Pyroscope profiling on `process_cpu:cpu:nanoseconds` is the recommended next step. |
| **Container resources** | Secondary to CPU spike — container CPU budget is consumed by the computation. Risk of throttling at higher load. |
| **DB connection pool** | Cascading effect of slower requests holding connections open longer. Not the root cause unless active count approaches pool maximum. |
| **Error rates** | If all errors hit `/flaky` URLs → test fixture noise, not a real regression. If on non-flaky endpoints, correlate with slowest compute sub-requests (timeouts from blocked threads). |
| **Throughput drops** | Secondary effect of latency — slower requests reduce achievable throughput under the same virtual user load. Not an independent root cause. |
| **Improvements** | The release fixed a previously failing dependency or retry logic. Explicitly note to preserve in any rollback. |

## Flaky endpoint detection

If ALL errors in `get_error_analysis.topErrorsByTransaction` have URLs matching `/flaky`,
set `allErrorsAreFlaky = true` and add this callout to the error section of the report:

> All errors originate from `/flaky` endpoints (Afterburner chaos fixture).
> These are **not real application errors** — classify as test infrastructure noise.
> Error rate regressions in Adapt are caused by the flaky endpoint firing more often
> under the higher load induced by the latency regression.
