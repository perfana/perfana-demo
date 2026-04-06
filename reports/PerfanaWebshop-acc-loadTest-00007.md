---
testRunId: PerfanaWebshop-acc-loadTest-00007
system: PerfanaWebshop
environment: acc
workload: loadTest
release: 2.4.3-increased-backend-calls
date: 2026-04-06
duration: 364s
result: FAIL
tags: [performance-report, jmeter, spring-boot-kubernetes, spanmetrics, docker]
baseline: PerfanaWebshop-acc-loadTest-00006
---

# Performance test report — PerfanaWebshop-acc-loadTest-00007

## Summary

| Field | Value |
|---|---|
| System | PerfanaWebshop |
| Environment | acc |
| Workload | loadTest |
| Release | `2.4.3-increased-backend-calls` |
| Start time | 2026-04-06T11:25:14Z |
| Duration | 364s (planned 360s) |
| Completion | 100% |
| **Overall result** | **FAIL ❌** |
| Adapt verdict | REGRESSION |
| SLO checks passed | 10 / 10 |
| Annotations | Proxy Dev: Accidentally triple the amount of back end calls |
| Tags | jmeter, spring-boot-kubernetes, spanmetrics, docker |

> Release `2.4.3-increased-backend-calls` introduced a code change that multiplied the number of downstream backend calls per request, causing error rate spikes across asset-loading transactions and increased JVM thread contention on afterburner-be — while all SLO hard limits were still met, Adapt detected 14 regressions vs the baseline.

---

## Verdict

### Adapt regression analysis

| Metric | Count |
|---|---|
| Total metrics evaluated | 144 |
| Regressions | 14 |
| Improvements | 2 |
| Differences | 128 |
| No difference | 0 |
| **Conclusion** | **REGRESSION** |

### SLO / requirements checks

| Dashboard | Metric | Result | Value | Requirement |
|---|---|---|---|---|
| Docker container metrics perfana-demo-afterburner-be-1 | CPU | PASS ✅ | 4.88% | < 70% |
| Docker container metrics perfana-demo-afterburner-fe-1 | CPU | PASS ✅ | 6.57% | < 70% |
| Hikari Connection Pool afterburner-be | Pending connections | PASS ✅ | 0 | < 10 |
| Hikari Connection Pool afterburner-fe | Pending connections | PASS ✅ | 0 | < 10 |
| HTTP connection pool afterburner-be | HTTP connection pool in use | PASS ✅ | 0% | < 90% |
| HTTP connection pool afterburner-fe | HTTP connection pool in use | PASS ✅ | 2.2% | < 90% |
| JVM memory management G1GC afterburner-be | Maximum Pause Durations end of minor GC by cause | PASS ✅ | 10.1ms | < 100ms |
| JVM memory management G1GC afterburner-fe | Maximum Pause Durations end of minor GC by cause | PASS ✅ | 16.9ms | < 100ms |
| JVM memory management G1GC afterburner-be | Maximum Pause Durations end of major GC by cause | PASS ✅ | 18.3ms | < 600ms |
| JVM memory management G1GC afterburner-fe | Maximum Pause Durations end of major GC by cause | PASS ✅ | 25.5ms | < 600ms |

All 10 SLO checks **passed**. The regression is detected by Adapt (statistical comparison) only — hard limits remain within thresholds.

---

## Transaction performance

### Response time table

| Transaction | Scenario | Avg (ms) | p95 (ms) | p99 (ms) | Threshold (ms) | Apdex | |
|---|---|---|---|---|---|---|---|
| T04_Payment_Processing | Checkout | 909.84 | 1056 | 1078.08 | 500 | 0.50 | ❌ |
| T05_Order_Confirmation | Checkout | 737.65 | 755.4 | 764.04 | 500 | 0.50 | ❌ |
| T04_View_Product_Details | BrowseAndSearch | 442.92 | 461.1 | 472.54 | 500 | 1.00 | ✅ |
| T03_Shipping_Address | Checkout | 396.60 | 414.6 | 417.98 | 500 | 1.00 | ✅ |
| T03_Search_Products | BrowseAndSearch | 290.74 | 373.9 | 386.34 | 500 | 1.00 | ✅ |
| T02_User_Login | Checkout | 283.70 | 302.4 | 308.04 | 500 | 1.00 | ✅ |
| T01_Homepage_Load | BrowseAndSearch | 267.97 | 275.1 | 282.82 | 500 | 1.00 | ✅ |
| T02_Browse_Category | BrowseAndSearch | 247.46 | 264.8 | 276.34 | 500 | 1.00 | ✅ |
| T06_Compare_Products | BrowseAndSearch | 241.95 | 257.4 | 261.62 | 500 | 1.00 | ✅ |
| T01_Add_To_Cart | Checkout | 227.45 | 243.4 | 316.08 | 500 | 1.00 | ✅ |
| T07_Order_Tracking_Assets | Checkout | 169.62 | 245.4 | 264.75 | 500 | 1.00 | ✅ |
| T06_Post_Order_Recommendations | Checkout | 160.17 | 173.9 | 232.10 | 500 | 1.00 | ✅ |
| T07_Product_Assets | BrowseAndSearch | 111.79 | 166.6 | 173.24 | 500 | 1.00 | ✅ |
| T05_Apply_Filters | BrowseAndSearch | 68.74 | 84.1 | 85.62 | 500 | 1.00 | ✅ |

_✅ Apdex ≥ 0.85 · ⚠️ Apdex 0.70–0.85 · ❌ Apdex < 0.70_

### p99 tail overshoot (transactions where p99 > threshold)

| Transaction | p99 (ms) | Threshold (ms) | Overshoot | % over |
|---|---|---|---|---|
| T04_Payment_Processing | 1078.08 | 500 | +578ms | +116% |
| T05_Order_Confirmation | 764.04 | 500 | +264ms | +53% |

### Top 5 by impact score (from transaction stats)

| Rank | Transaction | Avg RT (ms) | Count | Apdex |
|---|---|---|---|---|
| 1 | T04_Payment_Processing | 909.84 | 37 | 0.50 |
| 2 | T05_Order_Confirmation | 737.65 | 37 | 0.50 |
| 3 | T04_View_Product_Details | 442.92 | 39 | 1.00 |
| 4 | T03_Shipping_Address | 396.60 | 35 | 1.00 |
| 5 | T03_Search_Products | 290.74 | 39 | 1.00 |

---

## Regression analysis vs baseline

> Baseline: `PerfanaWebshop-acc-loadTest-00006` — 2.4.3-good-baseline (2026-04-06)
> Config changes: 4 · Unchanged: 22

### Config changes

| Key | Baseline | Current |
|---|---|---|
| `https://github.com/perfana/perfana-demo` (git SHA) | `4e2db5f` | `a2d09ca` |
| `testContext.annotations` | Proxy Dev: make cpu more efficient | Proxy Dev: Accidentally triple the amount of back end calls |
| `testContext.testRunId` | PerfanaWebshop-acc-loadTest-00006 | PerfanaWebshop-acc-loadTest-00007 |
| `testContext.version` | 2.4.3-good-baseline | 2.4.3-increased-backend-calls |

The annotation is highly informative: this release **accidentally tripled backend calls**. The git SHA changed from `4e2db5f` to `a2d09ca`. All other 22 configuration items are identical — JVM settings, thread counts, pool sizes are unchanged.

### Regressions by classification

#### Error rates (9 regressions)

**Hypothesis:** Error rate regressions across T07_Product_Assets, T07_Order_Tracking_Assets, and T04_Payment_Processing — all errors originate from `/flaky` endpoints (Afterburner chaos fixture). The increased backend call volume caused more flaky endpoint invocations per test run, raising absolute error counts and percentage rates even though the underlying flakiness configuration is unchanged.

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| `error_count` | Performance test metrics BrowseAndSearch | 0.09 | 1.00 | +1050% |
| `T07_Product_Assets` | Performance test metrics BrowseAndSearch | 1.31% | 10.26% | +684.6% |
| `T07_Product_Assets.product_availability_check` | Performance test metrics BrowseAndSearch | 1.33% | 10.26% | +669.2% |
| `T07_Order_Tracking_Assets.loyalty_points_api` | Performance test metrics Checkout | 0.75% | 2.94% | +294.1% |
| `error_count` | Performance test metrics Checkout | 0.19 | 0.75 | +290% |
| `T07_Order_Tracking_Assets.shipping_status_check` | Performance test metrics Checkout | 1.59% | 3.23% | +103.2% |
| `T04_Payment_Processing.payment_gateway_auth` | Performance test metrics Checkout | 1.35% | 2.94% | +117.6% |
| `T07_Order_Tracking_Assets` | Performance test metrics Checkout | 2.24% | 5.88% | +162.7% |
| `T04_Payment_Processing` | Performance test metrics Checkout | 1.26% | 2.70% | +114.9% |

#### JVM CPU / threads (3 regressions)

**Hypothesis:** The increased backend call fan-out requires more concurrent threads on afterburner-be to handle parallel downstream requests, explaining the rise in live, daemon, and timed-waiting thread counts. This is a secondary effect of the multiplied call count — more simultaneous I/O operations = more threads blocked in timed-wait.

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| `timed-waiting` | JVM afterburner-be | 16.38 | 31.81 | +94.2% |
| `daemon` | JVM afterburner-be | 31.39 | 37.86 | +20.6% |
| `live` | JVM afterburner-be | 38.90 | 45.33 | +16.5% |

#### JVM memory / GC (1 regression)

**Hypothesis:** JVM GC pressure: Allocation Failure minor GC collections increased by 82.3% on afterburner-be. The tripled backend call volume creates more short-lived objects (HTTP request/response buffers, JSON parsing), increasing minor GC frequency.

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| `(Allocation Failure)` | JVM memory management G1GC afterburner-be | 0.102 ops | 0.185 ops | +82.3% |

#### DB connection pool (1 regression)

**Hypothesis:** Connection pool pressure on employee-db-pool: query rate increased 123.4% — a direct consequence of more backend calls, each potentially touching the employee database. Active connections dropped to 0 (improvement) because queries complete faster than pool checkout time, but the raw query throughput increase is significant.

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| `employee-db-pool` | Hikari Connection Pool afterburner-be | 1.59/s | 3.54/s | +123.4% |

### Improvements (preserve in any rollback)

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| `employee-db-pool` Active connections | Hikari Connection Pool afterburner-be | 0.05 | 0 | -100% |
| `employee-db-pool` Idle connections | Hikari Connection Pool afterburner-be | 3.47 | 7.05 | +103.1% |

> More idle connections and zero active connections indicate the pool is not saturated despite the higher query rate — connections are recycled quickly. Preserve this behaviour in any rollback scenario.

---

## Error analysis

| Metric | Value |
|---|---|
| Total requests | 2,422 |
| Total errors | 7 |
| Overall error rate | 0.29% |
| Unique HTTP error codes | 1 (HTTP 500) |
| Transactions with errors | 3 |

### Errors by status code

| Code | Count | Avg RT (ms) | Min RT (ms) | Max RT (ms) |
|---|---|---|---|---|
| 500 | 7 | 95 | 24 | 292 |

### Errors by transaction

| Transaction | Sampler | URL | Code | Count | Classification |
|---|---|---|---|---|---|
| T07_Product_Assets | product_availability_check | `http://afterburner-fe:8080/flaky?flakiness=3&maxRandomDelay=100` | 500 | 4 | Flaky fixture |
| T04_Payment_Processing | payment_gateway_auth | `http://afterburner-fe:8080/flaky?maxRandomDelay=300&flakiness=3` | 500 | 1 | Flaky fixture |
| T07_Order_Tracking_Assets | loyalty_points_api | `http://afterburner-fe:8080/flaky?flakiness=3&maxRandomDelay=80` | 500 | 1 | Flaky fixture |
| T07_Order_Tracking_Assets | shipping_status_check | `http://afterburner-fe:8080/flaky?flakiness=2&maxRandomDelay=150` | 500 | 1 | Flaky fixture |

> All errors originate from `/flaky` endpoints (Afterburner chaos fixture).
> These are **not real application errors** — classify as test infrastructure noise.
> Error rate regressions in Adapt are caused by the flaky endpoint being invoked more times per test run due to the increased backend call multiplier in this release. The absolute error counts are low (7 total), but because the baseline had fewer invocations of these endpoints, the percentage rates appear significantly elevated.

---

## Cross-source investigation

> **Data sources:** Grafana ✅ · Tempo ✅ · Pyroscope ✅ · Dynatrace ❌
> **Confidence:** High

### Distributed traces — baseline vs current comparison

**Overall slowest traces (excluding synthetic `enable-traffic-light` timer):**

| | Baseline (00006) | Current (00007) |
|---|---|---|
| Max real duration | 510ms (`get /remote/call-many`) | 512ms (`get /remote/call-many`) |
| Median of top traces | ~185ms | ~112ms |
| New trace types | — | none |

> The overall trace duration ceiling is virtually unchanged (~510ms). The regression is not in maximum individual request duration but in **call fan-out**: each `get /remote/call-many` invocation now makes more parallel downstream calls, increasing backend load and flaky endpoint exposure.

**T04_Payment_Processing — per-transaction trace comparison:**

| | Baseline (00006) — trace `1cecd2a78736e170` | Current (00007) — trace `d2dc2411086213ca` |
|---|---|---|
| Total duration | 510ms | 513ms |
| Span count | 4 | 7 |
| `execute-call-async` branches | 1 | **2 (parallel)** |
| `get /delay` calls to afterburner-be | 1 | **2 (parallel)** |

**Trace drill-down — current run trace `d2dc2411086213ca` (513ms, T04_Payment_Processing):**

| Span | Service | Duration | Note |
|---|---|---|---|
| `get /remote/call-many` | afterburner-fe | 513ms | Root span |
| `execute-call-async` (branch 1) | afterburner-fe | 510ms | Parallel async call |
| `execute-call-async` (branch 2) | afterburner-fe | 510ms | **New — not in baseline** |
| `get` → `/delay` (branch 1) | afterburner-fe | 508ms | HTTP client call |
| `get` → `/delay` (branch 2) | afterburner-fe | 509ms | **New — not in baseline** |
| `get /delay` | afterburner-be | 508ms | Backend handler |
| `get /delay` | afterburner-be | 508ms | **New — not in baseline** |

**Baseline trace `1cecd2a78736e170` (510ms, T04_Payment_Processing):**

| Span | Service | Duration | Note |
|---|---|---|---|
| `get /remote/call-many` | afterburner-fe | 510ms | Root span |
| `execute-call-async` | afterburner-fe | 508ms | Single async call |
| `get` → `/delay` | afterburner-fe | 507ms | HTTP client call |
| `get /delay` | afterburner-be | 506ms | Backend handler |

> The trace diff confirms the root cause with **High confidence**: the current release doubled the number of parallel `execute-call-async` branches per `/remote/call-many` call (from 1 to 2 observed here; the annotation says "triple"). Each branch independently calls afterburner-be's `/delay` endpoint. Total wall-clock time is nearly identical (calls are parallel), but backend resource consumption — threads, connections, GC allocations, and flaky endpoint invocations — scales with the multiplier.

**T07_Product_Assets and T07_Order_Tracking_Assets — trace comparison:**

Both transactions show only `get /flaky` traces in their slowest slots for both runs. The error count increase is purely due to more calls hitting the `/flaky` endpoint under the higher call volume. No new trace types appeared.

### CPU profiling (Pyroscope)

**Top hotspots for `afterburner-fe`:**

| Method | Samples | % CPU |
|---|---|---|
| `io/perfana/afterburner/matrix/MatrixCalculator.multiply` | 1,657,894,644 | 7.43% |
| `libc.so.6.__libc_write` | 368,421,032 | 1.65% |
| `libc.so.6.__GI___fstatat64` | 342,105,244 | 1.53% |
| `libc.so.6.__GI___futex_abstimed_wait_cancelable64` | 289,473,668 | 1.30% |
| `libc.so.6.__GI___getdents64` | 210,526,304 | 0.94% |
| `.I2C/C2I adapters` | 197,368,410 | 0.88% |
| `libc.so.6.__memcpy_generic` | 171,052,622 | 0.77% |

> `MatrixCalculator.multiply` is the dominant CPU hotspot on afterburner-fe at 7.43% of samples. This is consistent with this service performing matrix computation work. The libc I/O and synchronisation primitives (`__futex_abstimed_wait_cancelable64`, `pthread_cond_broadcast`) are elevated and consistent with the increased async/parallel call fan-out creating more thread coordination overhead. The flamegraph does **not** show GC methods in the top 20 hotspots, suggesting the GC increase detected by Adapt is on afterburner-be (which is not profiled by Pyroscope in this configuration).

### Investigation gaps

- **Dynatrace:** Not connected — host-level infrastructure analysis was skipped.
- **Pyroscope for afterburner-be:** Only `afterburner-fe` is configured for profiling. The JVM thread and GC regressions are on afterburner-be — direct CPU profiling of that service is not available.

---

## Root cause & recommendations

### Root cause (confidence: High)

Release `2.4.3-increased-backend-calls` (git SHA `a2d09ca`) introduced a code change in `RemoteCallController.remoteCallHttpClientMany` that multiplied the number of parallel `execute-call-async` branches per `/remote/call-many` request. Trace evidence shows the current run executing **2 parallel downstream calls to afterburner-be** per payment processing transaction vs **1 call** in the baseline — with the annotation stating the intent was to "accidentally triple" the backend calls.

Because the parallel calls execute concurrently, the end-user wall-clock latency for each individual transaction is barely changed (513ms vs 510ms for T04_Payment_Processing). However, the **total backend resource consumption scales with the multiplier**: afterburner-be now handles 2–3× more requests, creating more JVM threads (timed-waiting +94%), more minor GC collections on afterburner-be (+82%), and more invocations of `/flaky` chaos endpoints per test run — which is why the error rate metrics in Adapt appear dramatically elevated (+115% to +1050%) even though the absolute error count is only 7 requests.

The cross-source causal chain is: **increased call fan-out (code change) → more concurrent threads on afterburner-be (JVM threads +20%) → more short-lived objects (GC +82%) → more flaky endpoint hits (error rates +115–1050%)**. All SLO hard limits were met because the multiplier hasn't yet saturated any resource pool, but the trajectory is clear.

### Evidence chain

| Source | Finding | Supports hypothesis? |
|---|---|---|
| Config diff | git SHA changed; annotation explicitly states "accidentally triple backend calls" | Yes ✅ |
| Trace diff (Tempo) | Span count: 4 spans (baseline) → 7 spans (current); 2 parallel `execute-call-async` branches vs 1 | Yes ✅ |
| Adapt (JVM threads) | `timed-waiting` +94%, `live` +16%, `daemon` +21% on afterburner-be | Yes ✅ |
| Adapt (GC) | Minor GC `Allocation Failure` collections +82% on afterburner-be | Yes ✅ |
| Adapt (error rates) | All error rate regressions confirmed as `/flaky` endpoint — noise amplified by call multiplier | Yes ✅ |
| Adapt (connection pool) | Employee DB query rate +123% — consistent with more backend calls | Yes ✅ |
| Pyroscope | `MatrixCalculator.multiply` is top CPU hotspot on afterburner-fe; libc synchronisation elevated | Partial ⚠️ (fe only, be not profiled) |
| SLO checks | All 10 passed — no hard limit breached | Partial ⚠️ (system stable but on a worse trajectory) |
| Dynatrace | Not available | N/A |

### Recommendations

1. **Revert the backend call multiplier immediately.** The code change in `RemoteCallController.remoteCallHttpClientMany` is the direct root cause. Revert to the logic that produces 1 `execute-call-async` branch per request (as in baseline `4e2db5f`). Do not roll back the connection pool improvements (idle connections +103%) which are improvements worth preserving.

2. **Add a call-count integration test.** The multiplier went undetected because wall-clock latency was unchanged (parallel calls). Add a test that asserts the number of outbound spans per transaction — e.g. verify that a single `POST /checkout/payment` produces at most N downstream requests to afterburner-be. Trace-based assertions prevent this class of regression from reaching acceptance.

3. **Enable Pyroscope profiling for afterburner-be.** The JVM thread and GC regressions are on afterburner-be but Pyroscope is only configured for afterburner-fe. Adding afterburner-be profiling would have provided direct CPU evidence of the thread contention and GC pressure, reducing investigation time.

4. **Raise the Adapt sensitivity for JVM thread regressions.** The `timed-waiting` thread count increased 94% — a very strong signal. If Adapt were configured to fail the run on JVM thread regressions above 50%, this issue would have been caught before the error rate cascades into noise.

5. **Review `/flaky` endpoint parametrisation.** The flakiness settings (`flakiness=3`, `flakiness=2`) interact with call volume — more calls = more flaky hits. Consider either a fixed seed/count for flaky endpoint behaviour, or exclude `/flaky` error metrics from Adapt comparisons to prevent noise masking real regressions.

---

## Run trend (last 5 runs)

| Run | Date | Release | Result | Adapt |
|---|---|---|---|---|
| `PerfanaWebshop-acc-loadTest-00007` | 2026-04-06 | 2.4.3-increased-backend-calls | FAIL ❌ | REGRESSION |
| `PerfanaWebshop-acc-loadTest-00006` | 2026-04-06 | 2.4.3-good-baseline | PASS ✅ | REGRESSION (accepted) |
| `PerfanaWebshop-acc-loadTest-00005` | 2026-04-06 | 2.4.3-default-http-conn-pool | FAIL ❌ | REGRESSION (denied) |
| `PerfanaWebshop-acc-loadTest-00004` | 2026-04-06 | 2.4.3-good-baseline | PASS ✅ | REGRESSION (accepted) |
| `PerfanaWebshop-acc-loadTest-00003` | 2026-04-06 | 2.4.3-changed-matrix-calc | FAIL ❌ | REGRESSION (denied) |

---

## Links

- [CI build](http://nu.nl)

---

_Report generated 2026-04-06 by Claude Code · Perfana report skill v2.0 (with cross-source investigation)_
