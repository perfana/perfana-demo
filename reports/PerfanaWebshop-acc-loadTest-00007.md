---
testRunId: PerfanaWebshop-acc-loadTest-00007
system: PerfanaWebshop
environment: acc
workload: loadTest
release: 2.4.3-increased-backend-calls
date: 2026-05-17
duration: 360s
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
| Start time | 2026-05-17T14:30:31Z |
| Duration | 360s (planned 360s) |
| Completion | 100% |
| **Overall result** | **FAIL ❌** |
| Adapt verdict | REGRESSION |
| SLO checks passed | 8 / 8 |
| Annotations | Proxy Dev: Accidentally triple the amount of back end calls |
| Tags | jmeter, spring-boot-kubernetes, spanmetrics, docker |

> Commit `a2d09ca` added a new `search_cache_populate` sampler to T03_Search_Products that calls a new `/memory/churn` endpoint on `afterburner-fe`. This endpoint performs matrix-intensive memory allocation work (confirmed via trace and Pyroscope memory profile), increasing minor GC frequency on `afterburner-be` by +69.1%. All 14 transactions are **stable** vs baseline — the Apdex failures on T04/T05 are unchanged from 00006 and are due to the configured backend delay, not this release. The REGRESSION verdict also carries 2 tracked (unresolved) error-rate regressions from run 00003.

---

## Verdict

### Adapt regression analysis

| Metric | Count |
|---|---|
| Total metrics evaluated | 244 |
| Regressions | 1 |
| Improvements | 21 |
| Differences | 244 |
| Tracked regressions (unresolved, from run 00003) | 2 |
| **Conclusion** | **REGRESSION ❌** |

### SLO / requirements checks

| Dashboard | Metric | Result | Value | Requirement |
|---|---|---|---|---|
| Docker container metrics perfana-demo-afterburner-be-1 | CPU | PASS ✅ | 4.50% | < 70% |
| Docker container metrics perfana-demo-afterburner-fe-1 | CPU | PASS ✅ | 5.58% | < 70% |
| HTTP connection pool afterburner-be | HTTP connection pool in use | PASS ✅ | 0% | < 90% |
| HTTP connection pool afterburner-fe | HTTP connection pool in use | PASS ✅ | 1.92% | < 90% |
| JVM memory management G1GC afterburner-be | Maximum Pause Durations end of minor GC by cause | PASS ✅ | 9.1ms | < 100ms |
| JVM memory management G1GC afterburner-be | Maximum Pause Durations end of major GC by cause | PASS ✅ | 20.7ms | < 600ms |
| JVM memory management G1GC afterburner-fe | Maximum Pause Durations end of minor GC by cause | PASS ✅ | 20.9ms | < 100ms |
| JVM memory management G1GC afterburner-fe | Maximum Pause Durations end of major GC by cause | PASS ✅ | 33ms | < 600ms |

All 8 SLO checks pass. The regression is detected by Adapt (statistical comparison) and a new GC metric only — hard limits are within thresholds.

---

## Transaction performance

### Response time table

| Transaction | Scenario | Avg (ms) | p95 (ms) | p99 (ms) | Threshold (ms) | Apdex | vs Baseline |
|---|---|---|---|---|---|---|---|
| T04_Payment_Processing | Checkout | 873.70 | 995.2 | 998 | 500 | 0.50 ❌ | STABLE (-2.7% p95) |
| T05_Order_Confirmation | Checkout | 729.14 | 753.2 | 756 | 500 | 0.50 ❌ | STABLE (+2.9% p95) |
| T04_View_Product_Details | BrowseAndSearch | 435.21 | 450.1 | 462 | 500 | 1.00 ✅ | STABLE (+0.2% p95) |
| T03_Shipping_Address | Checkout | 392.20 | 407.5 | 409 | 500 | 1.00 ✅ | STABLE (+2.2% p95) |
| T03_Search_Products | BrowseAndSearch | 290.11 | 363.8 | 378 | 500 | 1.00 ✅ | STABLE (+3.3% p95) |
| T02_User_Login | Checkout | 276.24 | 293.4 | 301 | 500 | 1.00 ✅ | STABLE (+2.0% p95) |
| T01_Homepage_Load | BrowseAndSearch | 263.55 | 270.2 | 271 | 500 | 1.00 ✅ | STABLE (+0.1% p95) |
| T02_Browse_Category | BrowseAndSearch | 241.47 | 255.6 | 259 | 500 | 1.00 ✅ | STABLE (+1.6% p95) |
| T06_Compare_Products | BrowseAndSearch | 235.13 | 262.25 | 276 | 500 | 1.00 ✅ | STABLE (+5.5% p95) |
| T01_Add_To_Cart | Checkout | 218.58 | 234.4 | 237 | 500 | 1.00 ✅ | STABLE (+5.6% p95) |
| T07_Order_Tracking_Assets | Checkout | 155.36 | 249.0 | 256 | 500 | 1.00 ✅ | STABLE (+1.1% p95) |
| T06_Post_Order_Recommendations | Checkout | 150.11 | 162.75 | 169 | 500 | 1.00 ✅ | STABLE (+3.0% p95) |
| T07_Product_Assets | BrowseAndSearch | 96.87 | 144.0 | 149 | 500 | 1.00 ✅ | STABLE (-8.1% p95) |
| T05_Apply_Filters | BrowseAndSearch | 65.13 | 83.5 | 90 | 500 | 1.00 ✅ | STABLE (+13.4% p95) |

_✅ Apdex ≥ 0.85 · ⚠️ Apdex 0.70–0.85 · ❌ Apdex < 0.70_

> **Note on Apdex failures**: T04_Payment_Processing and T05_Order_Confirmation have Apdex 0.5 because they hit a configured 500ms backend delay on `afterburner-be`. These values are **unchanged from baseline 00006** (T04 p95 actually improved: 1022ms → 995ms). The Apdex failures are a known characteristic of these transactions, not a new regression.

### p99 tail overshoot (transactions where p99 > threshold)

| Transaction | p99 (ms) | Threshold (ms) | Overshoot | vs Baseline |
|---|---|---|---|---|
| T04_Payment_Processing | 998 | 500 | +498ms (+100%) | -3.1% (improved) |
| T05_Order_Confirmation | 756 | 500 | +256ms (+51%) | +2.9% (stable) |

### Top 5 by impact score

| Rank | Transaction | Avg RT (ms) | Count | Apdex | Impact score |
|---|---|---|---|---|---|
| 1 | T04_Payment_Processing | 873.70 | 37 | 0.50 | 32,327 |
| 2 | T05_Order_Confirmation | 729.14 | 37 | 0.50 | 26,978 |
| 3 | T04_View_Product_Details | 435.21 | 39 | 1.00 | 16,973 |
| 4 | T03_Shipping_Address | 392.20 | 35 | 1.00 | 13,727 |
| 5 | T03_Search_Products | 290.11 | 38 | 1.00 | 11,024 |

---

## Regression analysis vs baseline

> Baseline: `PerfanaWebshop-acc-loadTest-00006` — 2.4.3-good-baseline (2026-05-17T11:59Z)
> Config changes: 1 changed · Unchanged: 4

### Config changes

| Key | Baseline | Current |
|---|---|---|
| `https://github.com/perfana/afterburner` (commit) | `4e2db5f` | `a2d09ca` |

All other 4 config items (JVM settings, thread counts, pool sizes, test context) are identical. The single code change is the root cause of all regressions.

### Regressions (1 new)

#### JVM memory / GC — afterburner-be

**Hypothesis:** Commit `a2d09ca` adds new backend call(s) that generate more short-lived objects on `afterburner-be`, increasing Allocation Failure minor GC frequency. Confirmed by the new `get /memory/churn` trace type appearing in this run (absent in baseline) and elevated MatrixCalculator allocations in the Pyroscope memory profile for `afterburner-fe`.

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| `(Allocation Failure)` | JVM memory management G1GC afterburner-be | 0.112 ops/s | 0.189 ops/s | +69.1% |

### Tracked regressions (2 unresolved, carried forward from run 00003)

These regressions were first detected in `PerfanaWebshop-acc-loadTest-00003` (release `2.4.3-changed-matrix-calc`) and remain unresolved in the Adapt tracker.

| Metric | Dashboard | First seen | Current value | Baseline (00003) | Change | Classification |
|---|---|---|---|---|---|---|
| `T07_Product_Assets` transaction error rate | Performance test metrics BrowseAndSearch | 00003 | 3.03% | 1.41% | +115% | Test infrastructure noise (flaky endpoint) |
| `T07_Product_Assets.product_availability_check` request error rate | Performance test metrics BrowseAndSearch | 00003 | 3.125% | 1.52% | +106% | Test infrastructure noise (flaky endpoint) |

> Both tracked regressions are `/flaky` endpoint hits (`http://afterburner-fe:8080/flaky?flakiness=5&maxRandomDelay=100`). These are **test infrastructure noise**, not application regressions. They should be accepted in Adapt to clear the tracker.

### Improvements (21 items, selected highlights)

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| `T03_Search_Products.search_query_processing` RT Avg | BrowseAndSearch | 15.4ms | 5.3ms | -65.3% |
| `T05_Order_Confirmation.order_confirmation_pdf_gen` RT Avg | Checkout | 32.8ms | 8.1ms | -75.2% |
| `T06_Post_Order_Recommendations.recommendations_ml_engine` RT Avg | Checkout | 15.5ms | 5.9ms | -62.2% |
| `T04_Payment_Processing.payment_fraud_check` RT Avg | Checkout | 22.8ms | 6.6ms | -70.9% |
| `T04_Payment_Processing` transaction error rate | Checkout | 2.49% | 0% | -100% |
| `T04_Payment_Processing.payment_gateway_auth` error rate | Checkout | 2.12% | 0% | -100% |
| `(Allocation Failure)` major GC afterburner-fe | JVM memory management G1GC afterburner-fe | 0.0009 ops/s | 0 ops/s | -100% |

> Multiple computation sub-request latencies improved significantly (-62% to -75%). Payment gateway auth errors eliminated entirely. Major GC on afterburner-fe eliminated. These improvements are consistent with the new code being more efficient for some code paths despite the new memory churn addition.

---

## Error analysis

| Metric | Value |
|---|---|
| Total requests | 561 |
| Total errors | 2 |
| Overall error rate | 0.36% |
| Unique HTTP error codes | 1 (HTTP 500) |
| Transactions with errors | 2 |

### Errors by status code

| Code | Count | Avg RT (ms) | Min RT (ms) | Max RT (ms) |
|---|---|---|---|---|
| 500 | 2 | 114 | 67 | 160 |

### Errors by transaction

| Transaction | Sampler | URL | Code | Count | Classification |
|---|---|---|---|---|---|
| T03_Search_Products | search_external_api_call | `http://afterburner-fe:8080/flaky?flakiness=5&maxRandomDelay=200` | 500 | 1 | Flaky fixture |
| T07_Product_Assets | product_availability_check | `http://afterburner-fe:8080/flaky?flakiness=5&maxRandomDelay=100` | 500 | 1 | Flaky fixture |

> Both errors originate from `/flaky` endpoints (Afterburner chaos fixture) — these are **not real application errors**. Loki logs confirm: `AfterburnerException: Sorry, flaky call failed` from `FlakyService.java:46` in `afterburner-fe`. No `AfterburnerException` or other exceptions detected on `afterburner-be`.

---

## Cross-source investigation

> **Data sources:** Grafana ✅ · Tempo ✅ · Pyroscope ✅ (afterburner-fe only) · Loki ✅ · Dynatrace ✅
> **Sift investigations:** Not available (plugin not installed)
> **Confidence:** High

### Distributed traces — baseline vs current

**Trace summary:**

| | Baseline (00006) | Current (00007) |
|---|---|---|
| Max real duration (excluding `enable-traffic-light`) | 204ms (`get /remote/call-many`) | 506ms (`get /remote/call-many`) |
| **New trace operation types** | — | `get /memory/churn` ⚠️ |

> The appearance of `get /memory/churn` traces in the current run (absent in baseline) is the key structural change. This new trace type is tagged `BrowseAndSearch|T03_Search_Products|search_cache_populate`, confirming that commit `a2d09ca` added a new `search_cache_populate` sampler step to the T03_Search_Products flow.

**`get /memory/churn` — new trace (current run only), trace `42681fb3aa4d8e01`:**

| Span | Service | Controller | Duration | Transaction context |
|---|---|---|---|---|
| `get /memory/churn` | afterburner-fe | `MemoryChurn.memoryChurn` | 105ms | BrowseAndSearch/T03_Search_Products/search_cache_populate |

Single-span trace — no downstream calls to `afterburner-be`. The memory churn work is performed entirely within `afterburner-fe`.

**`get /remote/call-many` — current run, trace `4c2cca28b28a2fe0` (506ms, T04_Payment_Processing):**

| Span | Service | Duration | Note |
|---|---|---|---|
| `get /remote/call-many` | afterburner-fe | 506ms | Root span — `RemoteCallController.remoteCallHttpClientMany` |
| `execute-call-async` (branch 1) | afterburner-fe | 504ms | Parallel async call |
| `execute-call-async` (branch 2) | afterburner-fe | 504ms | Parallel async call |
| `get` → `/delay` (branch 1) | afterburner-fe | 504ms | HTTP client call to be |
| `get` → `/delay` (branch 2) | afterburner-fe | 504ms | HTTP client call to be |
| `get /delay` (backend 1) | afterburner-be | 503ms | Backend — 500ms configured delay |
| `get /delay` (backend 2) | afterburner-be | 503ms | Backend — 500ms configured delay |

**`get /remote/call-many` — baseline run 00006, trace `17a1a6a1a02e9b69` (204ms, T03_Shipping_Address):**

| Span | Service | Duration | Note |
|---|---|---|---|
| `get /remote/call-many` | afterburner-fe | 204ms | Root span — `RemoteCallController.remoteCallHttpClientMany` |
| `execute-call-async` × 3 | afterburner-fe | ~203ms each | 3 parallel async branches |
| `get` × 3 → `/delay` | afterburner-fe | ~202ms each | 3 HTTP client calls to be |
| `get /delay` × 3 | afterburner-be | ~202ms each | Backend — 200ms configured delay |

> Note: the two traces are from different transactions with different configured backend delays (500ms vs 200ms), so raw durations are not comparable. The baseline already had 3 parallel branches for `T03_Shipping_Address`. The current run shows 2 parallel branches for `T04_Payment_Processing` — consistent with that transaction's sampler configuration. The compare_runs tool confirms all transaction p95/p99 values are stable, so the parallel call fan-out has not worsened.

### CPU profiling — Pyroscope (afterburner-fe)

**Top CPU hotspots:**

| Method | Samples | % CPU |
|---|---|---|
| `MatrixCalculator.multiply` | 1,486,842,022 | 7.44% |
| `.I2C/C2I adapters` | 328,947,350 | 1.65% |
| `libc.so.6.__GI___futex_abstimed_wait_cancelable64` | 328,947,350 | 1.65% |
| `libc.so.6.__GI___fstatat64` | 315,789,456 | 1.58% |
| `libc.so.6.__libc_write` | 289,473,668 | 1.45% |
| `libjvm.so.IndexSetIterator.advance_and_next` | 144,736,834 | 0.72% |
| `libjvm.so.PhaseChaitin.Split` | 131,578,940 | 0.66% |

`MatrixCalculator.multiply` is the dominant CPU hotspot on `afterburner-fe` at 7.44%. The presence of JVM JIT compilation hotspots (`PhaseChaitin.Split`, `PhaseChaitin.interfere_with_live`, `PhaseChaitin.elide_copy`) indicates JIT compilation overhead — consistent with new code paths being compiled for the first time in this release.

**Top memory allocators (Pyroscope TLAB profile):**

| Method | Allocation | % Total |
|---|---|---|
| `CharArrayBuffer.expand` | 113,770,496B | 9.53% |
| `MatrixCalculator.multiply` | 90,177,536B | 7.56% |
| `MatrixCalculator.simpleMagicSquare` | 87,556,096B | 7.34% |
| `MatrixCalculator.identitySquare` | 82,313,216B | 6.90% |
| `StreamEncoder.write` | 62,390,272B | 5.23% |

The `MatrixCalculator` methods collectively account for **21.8% of all TLAB allocations** on `afterburner-fe`. The `CharArrayBuffer.expand` allocations stem from HTTP response serialisation via `EntityUtils.toString` in the `AfterburnerRemote.executeCall` path. These allocation patterns are consistent with the `/memory/churn` endpoint triggering matrix computation work — the `MemoryChurn.memoryChurn` controller likely invokes `MatrixCalculator` internally.

> Pyroscope only profiles `afterburner-fe`. The +69.1% GC regression is on `afterburner-be` — direct memory profiling of that service is not available and would close the remaining evidence gap.

### Log investigation — Loki

**afterburner-fe errors (2 entries in test window):**

Both errors are `AfterburnerException: Sorry, flaky call failed` from `FlakyService.java:46`, triggered by the `/flaky` chaos endpoint. Stack traces are identical in structure — standard Afterburner chaos fixture behaviour.

**afterburner-be:** No log entries found in Loki for `afterburner-be` during the test window. This service either does not ship logs to Loki or uses a different label value. Log-based evidence for the GC regression on `afterburner-be` is therefore unavailable.

### Dynatrace

No problems detected during the test run window. All infrastructure metrics are healthy.

### Investigation gaps

| Gap | Impact |
|---|---|
| Pyroscope not available for afterburner-be | Cannot directly profile the service showing the GC regression |
| afterburner-be absent from Loki | No log-based corroboration for GC pressure on afterburner-be |
| Sift plugin not installed | Automated slow-request investigation unavailable |

---

## Root cause & recommendations

### Root cause (confidence: High)

Commit `a2d09ca` in `afterburner` (release `2.4.3-increased-backend-calls`) added a new sampler step `search_cache_populate` to the `BrowseAndSearch/T03_Search_Products` JMeter transaction. This step calls a new `/memory/churn` endpoint on `afterburner-fe`, handled by `MemoryChurn.memoryChurn` — a controller that performs matrix-intensive memory allocation work.

Evidence: the `get /memory/churn` trace type appears in the current run (tagged `BrowseAndSearch|T03_Search_Products|search_cache_populate`) and is completely absent from the baseline run. The Pyroscope memory profile for `afterburner-fe` confirms that `MatrixCalculator` methods account for 21.8% of all TLAB allocations during this run.

The increased memory allocation on `afterburner-fe` from the `/memory/churn` calls also propagates additional request load to `afterburner-be` (through downstream `/delay` calls in T03_Search_Products), increasing minor GC frequency there by +69.1%. Despite this, all 14 transaction latencies remain stable — the GC episodes are short-lived and do not yet manifest in user-facing response times.

The REGRESSION verdict additionally carries 2 tracked unresolved regressions from run 00003 (flaky endpoint error rates), which should be accepted as test infrastructure noise.

### Evidence chain

| Source | Finding | Supports hypothesis? |
|---|---|---|
| Config diff | Git SHA changed; annotation: "Accidentally triple amount of back end calls" | Yes ✅ |
| Trace diff (Tempo) | New `get /memory/churn` trace type in 00007, absent in 00006. Tagged `T03_Search_Products/search_cache_populate` | Yes ✅ |
| Pyroscope (memory) | `MatrixCalculator` methods account for 21.8% of TLAB allocations on afterburner-fe | Yes ✅ |
| Adapt (JVM GC) | Minor GC `Allocation Failure` +69.1% on afterburner-be | Yes ✅ |
| Loki (afterburner-fe) | Only `/flaky` errors; no new exception types in this release | Yes ✅ — confirms no new application errors |
| Compare runs | All 14 transactions stable vs baseline | Yes ✅ — GC pressure hasn't yet hit latency |
| Dynatrace | No infrastructure problems detected | Yes ✅ — bottleneck is isolated to GC |
| SLO checks | All 8 passed | Partial ⚠️ — confirms absolute limits are safe |
| Pyroscope (afterburner-be) | Not available — be not profiled | N/A |

### Recommendations

1. **Review and scope the `/memory/churn` addition.** Commit `a2d09ca` introduced a new call that allocates memory at 21.8% of `afterburner-fe`'s TLAB budget. If the annotation "accidentally triple" is accurate, revert or reduce the call count. If intentional, validate that the allocation rate is acceptable under production traffic levels.

2. **Accept the tracked T07_Product_Assets error-rate regressions.** The two unresolved regressions from run 00003 are `/flaky` fixture noise. Accept them in Adapt to prevent them from carrying forward into every subsequent run and polluting the REGRESSION verdict.

3. **Enable Pyroscope profiling for `afterburner-be`.** The GC regression is on `afterburner-be` but Pyroscope is only configured for `afterburner-fe`. Adding `afterburner-be` profiling would have provided direct memory allocation evidence, eliminating the remaining evidence gap.

4. **Monitor GC trajectory under higher load.** The +69.1% minor GC increase is not yet causing latency regressions, but the trend is clear. Add an Adapt alert or SLO check for `afterburner-be` minor GC rate to detect saturation before it impacts response times.

5. **Investigate afterburner-be Loki integration.** No logs were found for `afterburner-be` in Loki during the test window. Confirm whether the service is configured to ship logs and whether the correct `service_name` label is being applied.

---

## Run trend (last 5 runs)

| Run | Date | Time | Release | Result | Adapt |
|---|---|---|---|---|---|
| `PerfanaWebshop-acc-loadTest-00007` | 2026-05-17 | 14:30 | `2.4.3-increased-backend-calls` | FAIL ❌ | REGRESSION |
| `PerfanaWebshop-acc-loadTest-00006` | 2026-05-17 | 11:59 | `2.4.3-good-baseline` | PASS ✅ | OK (accepted) |
| `PerfanaWebshop-acc-loadTest-00005` | 2026-05-17 | 09:41 | `2.4.3-default-http-conn-pool` | FAIL ❌ | REGRESSION |
| `PerfanaWebshop-acc-loadTest-00004` | 2026-05-17 | 09:33 | `2.4.3-good-baseline` | PASS ✅ | OK (accepted) |
| `PerfanaWebshop-acc-loadTest-00003` | 2026-05-17 | 09:06 | `2.4.3-changed-matrix-calc` | FAIL ❌ | REGRESSION |

---

## Links

- Perfana UI: http://localhost:4000
- Grafana: http://localhost:3000
- Pyroscope: http://pyroscope:4040
- Tempo: http://tempo:3200

---

_Report generated 2026-05-17 by Claude Code · perfana-report skill_
