# Performance Test Report: PerfanaWebshop-acc-loadTest-00003

## Summary

| Field | Value |
|---|---|
| **Test Run ID** | PerfanaWebshop-acc-loadTest-00003 |
| **System Under Test** | PerfanaWebshop |
| **Environment** | acc |
| **Workload** | loadTest |
| **Application Release** | 2.4.3-changed-matrix-calc |
| **Start Time** | 2026-05-17T15:52:39 UTC |
| **End Time** | 2026-05-17T15:58:40 UTC |
| **Duration** | 360s (ramp-up 60s excluded from analysis) |
| **Overall Result** | FAIL |
| **Adapt Verdict** | REGRESSION |
| **SLO Result** | PASS (all 8 requirements met) |
| **Baseline Run** | PerfanaWebshop-acc-loadTest-00002 (2.4.3-good-baseline) |
| **Annotation** | "Proxy Dev: make matrix calculation more variable" |
| **Tags** | jmeter, spring-boot-kubernetes, spanmetrics, docker |

**Verdict: The run failed Adapt regression detection. All SLO checks passed, but 61 metric regressions were detected relative to the baseline. The root cause is a change to `MatrixCalculator.multiply` in `afterburner-fe`, introduced in commit `26361d2` of the afterburner repository. This single code change caused CPU consumption on `afterburner-fe` to spike from 5% to 14% (+180%), drove GC minor collection frequency up by 107%, and inflated sub-request latencies across every transaction by 200–3400%. Do not promote to production.**

---

## MCP Preflight

| Source | Status |
|---|---|
| Perfana MCP | Available |
| Grafana MCP | Available |
| Tempo (via Grafana Sift) | Unavailable — Sift plugin not installed. Trace data accessed via Perfana wrappers only. |
| Loki (via Grafana) | Available |
| Pyroscope (via Grafana) | Unavailable — datasource UID not resolvable via Grafana MCP. Hotspot data accessed via Perfana wrappers only. |

---

## Overall Results

| Metric | Value |
|---|---|
| Adapt verdict | REGRESSION |
| Total regressions | 61 |
| Total improvements | 6 |
| Total differences evaluated | 412 |
| SLO checks | All 8 passed |
| Error rate (overall) | 0.54% (3 errors / 560 requests) |
| Tracked regressions | 0 unresolved |

---

## Transaction Statistics

| Transaction | Scenario | Avg RT (ms) | p95 (ms) | p99 (ms) | p99 overshoot | Errors | Apdex | Threshold |
|---|---|---|---|---|---|---|---|---|
| T04_Payment_Processing | Checkout | 1086.76 | 1521.95 | 1614 | **+1114ms** | 0% | 0.500 | 500ms |
| T05_Order_Confirmation | Checkout | 897.68 | 1231.85 | 1458 | **+958ms** | 0% | 0.500 | 500ms |
| T04_View_Product_Details | BrowseAndSearch | 452.42 | 493.00 | 601 | +101ms | 0% | 0.981 | 500ms |
| T03_Search_Products | BrowseAndSearch | 418.47 | 545.00 | 562 | +62ms | **7.89%** | 0.932 | 500ms |
| T03_Shipping_Address | Checkout | 410.29 | 459.50 | 473 | within | 0% | 1.000 | 500ms |
| T02_User_Login | Checkout | 328.88 | 413.25 | 442 | within | 0% | 1.000 | 500ms |
| T06_Compare_Products | BrowseAndSearch | 275.90 | 339.55 | 408 | within | 0% | 1.000 | 500ms |
| T01_Homepage_Load | BrowseAndSearch | 279.68 | 310.00 | 324 | within | 0% | 1.000 | 500ms |
| T02_Browse_Category | BrowseAndSearch | 255.67 | 406.50 | 429 | within | 0% | 1.000 | 500ms |
| T01_Add_To_Cart | Checkout | 234.06 | 324.05 | 518 | +18ms | 0% | 0.991 | 500ms |
| T06_Post_Order_Recommendations | Checkout | 203.66 | 336.00 | 436 | within | 0% | 1.000 | 500ms |
| T07_Order_Tracking_Assets | Checkout | 178.67 | 235.85 | 260 | within | 0% | 1.000 | 500ms |
| T07_Product_Assets | BrowseAndSearch | 99.03 | 158.20 | 276 | within | 0% | 1.000 | 500ms |
| T05_Apply_Filters | BrowseAndSearch | 89.62 | 110.55 | 515 | +15ms | 0% | 0.993 | 500ms |

---

## Baseline Comparison (vs PerfanaWebshop-acc-loadTest-00002)

| Transaction | Status | p95 Baseline | p95 Current | p95 Delta | p99 Delta |
|---|---|---|---|---|---|
| T06_Post_Order_Recommendations | regression | 161.1ms | 336ms | **+108.6%** | +165.9% |
| T05_Order_Confirmation | regression | 739.6ms | 1231.85ms | **+66.6%** | +93.4% |
| T02_Browse_Category | regression | 252.8ms | 406.5ms | **+60.8%** | +59.5% |
| T04_Payment_Processing | regression | 1006.95ms | 1521.95ms | **+51.1%** | +59.0% |
| T05_Apply_Filters | regression | 73ms | 110.55ms | +51.4% | +605.5% |
| T03_Search_Products | regression | 366.8ms | 545ms | +48.6% | +51.9% |
| T02_User_Login | regression | 284ms | 413.25ms | +45.5% | +53.5% |
| T01_Add_To_Cart | regression | 225ms | 324.05ms | +44.0% | +125.2% |
| T06_Compare_Products | regression | 244ms | 339.55ms | +39.2% | +64.5% |
| T04_View_Product_Details | stable | 440ms | 493ms | +12.0% | +35.4% |
| T03_Shipping_Address | stable | 400.75ms | 459.5ms | +14.7% | +17.4% |
| T01_Homepage_Load | stable | 271.55ms | 310ms | +14.2% | +17.4% |
| T07_Product_Assets | stable | 154.1ms | 158.2ms | +2.7% | +75.8% |
| T07_Order_Tracking_Assets | stable | 244.4ms | 235.85ms | -3.5% | +4.8% |

**Improvements:** T04_Payment_Processing error rate -100% (was 2.7% in baseline); T07_Product_Assets error rate -100% (was 2.6%).

**Config diff — one change:**

| Key | Baseline | Current |
|---|---|---|
| https://github.com/perfana/afterburner | `4e2db5f` | `26361d2` |

---

## SLO Check Results

All 8 SLO checks passed.

| Dashboard | Panel | Requirement | Actual | Result |
|---|---|---|---|---|
| Docker container metrics afterburner-be-1 | CPU Usage | < 70% | 3.51% | PASS |
| Docker container metrics afterburner-fe-1 | CPU Usage | < 70% | **14.15%** | PASS |
| HTTP connection pool afterburner-be | Pool in use | < 90% | 0% | PASS |
| HTTP connection pool afterburner-fe | Pool in use | < 90% | 1.75% | PASS |
| JVM G1GC afterburner-be | Max pause major GC | < 0.6s | 0.029s | PASS |
| JVM G1GC afterburner-be | Max pause minor GC | < 0.1s | 0.010s | PASS |
| JVM G1GC afterburner-fe | Max pause major GC | < 0.6s | 0.034s | PASS |
| JVM G1GC afterburner-fe | Max pause minor GC | < 0.1s | 0.016s | PASS |

Note: While GC pause durations are within thresholds, minor GC collection *frequency* on `afterburner-fe` regressed by +107.3% (Adapt-detected, not covered by SLO). GC is running more often due to increased allocation pressure from the heavier matrix computation.

---

## Adapt Regression Analysis

### By Dashboard / Source Type

| Dashboard | Source Type | Regressions | Top Metric | Change % |
|---|---|---|---|---|
| Performance test metrics Checkout | Performance test | 13 | T05_Order_Confirmation.order_confirmation_pdf_gen | +1987% |
| Performance test metrics BrowseAndSearch | Performance test | 12 | T03_Search_Products.search_query_processing | +2201.5% |
| Span metrics (matrix-multiply, 14 dashboards) | Span metrics | 14 | T04_Payment_Processing/payment_fraud_check matrix-multiply | +3111.9% |
| Span metrics (/cpu/magic-identity-check, 12 dashboards) | Span metrics | 12 | T04_Payment_Processing/payment_fraud_check magic-identity-check | +1739.2% |
| Span metrics (other, 4 dashboards) | Span metrics | 6 | /flaky, /memory/churn, /remote/call-many | +27–135% |
| JVM memory management G1GC afterburner-fe | JVM monitoring | 1 | Minor GC collections (Allocation Failure) | +107.3% |
| Docker container metrics afterburner-fe-1 | Infrastructure | 1 | CPU Usage | +179.8% |
| Span metrics /flaky (2 dashboards) | Span metrics | 2 | afterburner-fe \| get /flaky | +111.7–135.5% |

### Top Sub-Request Regressions

| Sub-Request | Classification | Change % | Current | Baseline |
|---|---|---|---|---|
| T03_Search_Products.search_query_processing | Computation kernel | +2201.5% | 122.52ms | 5.32ms |
| T05_Order_Confirmation.order_confirmation_pdf_gen | Request latency | +1987.0% | 182.88ms | 8.76ms |
| T04_Payment_Processing.payment_card_encryption | Request latency | +1351.9% | 90.27ms | 6.22ms |
| T04_Payment_Processing.payment_fraud_check | Request latency | +1344.8% | 97.03ms | 6.72ms |
| T06_Post_Order_Recommendations.recommendations_ml_engine | Computation kernel | +1124.2% | 68.96ms | 5.63ms |
| T02_User_Login.login_credential_hash | Computation kernel | +711.3% | 45.61ms | 5.62ms |
| T03_Search_Products.search_results_ranking | Computation kernel | +699.0% | 31.53ms | 3.95ms |
| T06_Compare_Products.compare_feature_matrix_compute | Computation kernel | +673.6% | 53.59ms | 6.93ms |
| T01_Homepage_Load.homepage_recommendations_compute | Computation kernel | +435.2% | 18.97ms | 3.54ms |
| T02_Browse_Category.category_filter_options_compute | Computation kernel | +290.5% | 12.00ms | 3.07ms |
| Docker CPU afterburner-fe | Container resources | +179.8% | 14.15% | 5.06% |
| JVM minor GC collections afterburner-fe | JVM memory / GC | +107.3% | 0.344 ops | 0.166 ops |

### Causal Chains (from Adapt)

| Chain | Confidence |
|---|---|
| Compute regressions (perf test) → CPU spike (container) → GC pressure (JVM) | **High** |
| Latency regression (perf test) → container resource saturation | **High** |

---

## Error Analysis

**Total errors: 3 (error rate: 0.54%)**

All 3 errors are HTTP 500 responses to a single endpoint:

| Transaction | Sampler | URL | Count | Avg RT |
|---|---|---|---|---|
| T03_Search_Products | search_external_api_call | `/flaky?flakiness=5&maxRandomDelay=200` | 3 | 135ms |

**Error detail:** `io.perfana.afterburner.AfterburnerException` thrown from `FlakyService.flaky(FlakyService.java:46)`. Message pattern: "Sorry, flaky call failed after N milliseconds."

**Flaky error flag: TRUE** — all errors match the `/flaky` endpoint. This is deterministic probabilistic failure simulation (`flakiness=5` = ~5% failure rate). The Adapt error rate regression on T03 (+388%) is statistical variance on a small sample, not a new failure mode. Confirmed by Loki: exactly 3 `AfterburnerException` stack traces found, no new exception types.

---

## Root Cause Investigation

### Pyroscope Hotspots — afterburner-fe

**Current run (PerfanaWebshop-acc-loadTest-00003):**

| Rank | Function | CPU Samples | % of Total CPU |
|---|---|---|---|
| 1 | `io/perfana/afterburner/matrix/MatrixCalculator.multiply` | 30,749,998,278 | **64.58%** |
| 2 | `.I2C/C2I adapters` | 263,157,880 | 0.55% |
| 3 | `libjvm.so.PhaseChaitin::Split` | 171,052,622 | 0.36% |
| 17 | `io/perfana/afterburner/matrix/MatrixCalculator.simpleMagicSquare` | 92,105,258 | 0.19% |

**Baseline run (PerfanaWebshop-acc-loadTest-00002):**

| Rank | Function | CPU Samples | % of Total CPU |
|---|---|---|---|
| 1 | `io/perfana/afterburner/matrix/MatrixCalculator.multiply` | 1,065,789,414 | **6.18%** |
| 2 | `.I2C/C2I adapters` | 328,947,350 | 1.91% |

**Key finding:** `MatrixCalculator.multiply` consumed 6.2% of CPU in the baseline and 64.6% in the current run — a ~10x increase in CPU share. In the current run, this single method completely dominates all CPU time. The `simpleMagicSquare` sub-method also appears in the top 20, absent from the baseline top 5, confirming the matrix algorithm changed in a way that involves more work per call.

### Span Metrics Evidence

The `afterburner-fe | matrix-multiply` span is regressed across all 14 compute-heavy sub-request dashboards, confirming the change is applied universally:

| Sub-Request | matrix-multiply p95 baseline | matrix-multiply p95 current | Change % |
|---|---|---|---|
| T04_Payment_Processing/payment_fraud_check | 0.007s | 0.223s | +3111.9% |
| T03_Search_Products/search_results_ranking | 0.002s | 0.066s | +3377.5% |
| T03_Search_Products/search_query_processing | 0.004s | 0.105s | +2580% |
| T02_User_Login/login_credential_hash | 0.003s | 0.080s | +2438.1% |
| T05_Order_Confirmation/recommendations_ml_engine | 0.004s | 0.104s | +2564.1% |
| T04_Payment_Processing/payment_card_encryption | 0.004s | 0.125s | +3100.0% |

The `afterburner-fe | get /cpu/magic-identity-check` span is also regressed by 300–1739% across all compute sub-requests, corroborating that the CPU-bound computation path was broadened.

### Trace Evidence

**Current run — T04_Payment_Processing slow traces (top 5):**
- All 5 rooted at `get /remote/call-many`, max 511ms, avg ~507ms
- Root service: afterburner-fe

**Baseline run — T04_Payment_Processing slow traces (top 5):**
- Top 2 rooted at `get /remote/call-many`, max 507ms
- Remaining 3 rooted at `get /flaky` (~281ms max) — flaky endpoint operations

**Trace diff:** Max trace duration for `/remote/call-many` is similar between runs (511ms vs 507ms). However, Adapt confirms T04 transaction avg grew from ~724ms to ~1087ms. The slow traces reflect individual sub-request ceilings, not the full transaction time. The matrix computation CPU overhead inflates every sub-request, causing the cumulative transaction latency to grow even when no single span exceeds the trace filter threshold.

### Loki Log Evidence

| Evidence | Finding |
|---|---|
| ERROR log count | 3 entries — exactly matching the 3 JMeter-reported errors |
| Exception type | `io.perfana.afterburner.AfterburnerException` only — same class as baseline |
| Exception origin | `FlakyService.java:46` — the intentional flakiness endpoint |
| WARN log count | 3 entries — Spring MVC `ExceptionHandlerExceptionResolver` resolved them cleanly |
| New exception types | None — no `OutOfMemoryError`, no `HikariPool`, no new failure modes |
| Total lines scanned | 4,065 in the run window |

Note: Loki pattern detection returned 404 (endpoint not available in this deployment). Log stats API returned 0 for label selector (known quirk). Raw log queries succeeded.

### Infrastructure Evidence

| Metric | Baseline | Current | Change |
|---|---|---|---|
| afterburner-fe container CPU | 5.06% | 14.15% | +179.8% |
| afterburner-be container CPU | ~3.5% | 3.51% | stable |
| HTTP connection pool fe | — | 1.75% | within threshold |
| HTTP connection pool be | — | 0% | within threshold |
| Dynatrace problems | — | 0 detected | no infrastructure failure |

The CPU regression is isolated to `afterburner-fe` — `afterburner-be` is unaffected, which is consistent with the matrix computation residing entirely in the fe service.

---

## Evidence Correlation

| Source | Evidence | Confidence |
|---|---|---|
| Config diff | Commit `26361d2` — annotation: "make matrix calculation more variable" | Confirmed (code change identified) |
| Pyroscope hotspots | `MatrixCalculator.multiply` 6.2% → 64.6% CPU — ~10x absolute increase | **Primary cause — High** |
| Span metrics | `matrix-multiply` span +2500–3400% across all 14 compute sub-request dashboards | **High** (2nd independent source) |
| Infrastructure | afterburner-fe CPU +179.8%, be unaffected | **High** (3rd independent source) |
| JVM GC | Minor GC collection frequency +107.3% on fe, GC pause durations within threshold | Downstream effect — Medium |
| Adapt causal chain | Compute regression → CPU spike → GC pressure confirmed with High confidence | Confirmed |
| Loki logs | Only FlakyService exceptions; no new error types introduced | Rules out other failure modes |
| Dynatrace | No problems detected | No infrastructure-level failure |
| Trace comparison | Consistent max duration for /remote/call-many spans | Consistent with CPU-bound inflation of aggregate |

---

## Root Cause

**Confidence: High — corroborated by 4 independent data sources**

The sole root cause is a change to `MatrixCalculator.multiply` in `afterburner-fe`, introduced in commit `26361d2` (baseline: `4e2db5f`). The new implementation performs substantially more computation per call — likely using a variable, larger matrix — causing:

1. **`MatrixCalculator.multiply` to consume 64.6% of all CPU time** (up from 6.2% — ~10x increase)
2. **All 14 compute sub-requests to regress by 200–3400%** in sub-request latency
3. **Container CPU on `afterburner-fe` to triple** (5.1% → 14.2%)
4. **JVM minor GC collection frequency on `afterburner-fe` to double** (+107%) due to increased allocation from the larger matrix
5. **T04_Payment_Processing and T05_Order_Confirmation Apdex to drop to 0.5** with p99 response times of 1614ms and 1458ms — exceeding the 500ms threshold by 1114ms and 958ms respectively

The errors on T03_Search_Products are entirely unrelated — they are probabilistic flaky behaviour from the `/flaky` endpoint, confirmed by Loki stack traces showing `FlakyService.java:46` as the only error origin.

---

## Performance Rankings

### Slowest Transactions

| Rank | Transaction | Scenario | Avg RT | p95 | Error % | Apdex |
|---|---|---|---|---|---|---|
| 1 | T04_Payment_Processing | Checkout | 1086.76ms | 1521.95ms | 0% | 0.500 |
| 2 | T05_Order_Confirmation | Checkout | 897.68ms | 1231.85ms | 0% | 0.500 |
| 3 | T04_View_Product_Details | BrowseAndSearch | 452.42ms | 493ms | 0% | 0.981 |
| 4 | T03_Search_Products | BrowseAndSearch | 418.47ms | 545ms | 7.89% | 0.932 |
| 5 | T03_Shipping_Address | Checkout | 410.29ms | 459.5ms | 0% | 1.000 |

### Highest Impact (avg RT x count)

| Rank | Transaction | Scenario | Impact Score |
|---|---|---|---|
| 1 | T04_Payment_Processing | Checkout | 40,210 |
| 2 | T05_Order_Confirmation | Checkout | 33,214 |
| 3 | T04_View_Product_Details | BrowseAndSearch | 17,192 |
| 4 | T03_Search_Products | BrowseAndSearch | 15,902 |
| 5 | T03_Shipping_Address | Checkout | 14,360 |

### Error Rate Ranking

| Rank | Transaction | Scenario | Error % |
|---|---|---|---|
| 1 | T03_Search_Products | BrowseAndSearch | 7.89% |
| 2–14 | All others | — | 0% |

---

## Data Quality Notes

- **Sparse data warning:** 2 JVM metrics on `afterburner-be` had fewer than 5 data points (Metadata GC Threshold: 3 points and 2 points at 15s timestep). The be-side GC analysis should be treated as indicative only.
- **Adapt mode:** DEFAULT — differences have not yet been accepted (TBD).
- **Tempo via Grafana Sift:** unavailable — Sift plugin not installed. Trace queries used Perfana wrappers only.
- **Pyroscope via Grafana:** unavailable — datasource UID not resolvable. Hotspot data used Perfana wrappers only.
- **Loki pattern detection:** 404 from Loki API — patterns endpoint not available. Raw log queries succeeded.
- **Loki stats:** returned 0 entries for label selector — known quirk with stats API label indexing. Direct log queries confirmed data presence (3 ERROR entries returned).

---

## Recommendations

### Block promotion (immediate)

1. **Revert or fix commit `26361d2` in the afterburner repository.** The change annotation "make matrix calculation more variable" introduced heavier matrix computation that consumes 65% of CPU under load. The prior commit `4e2db5f` ("make cpu more efficient") is the known-good baseline.

2. **Do not promote `2.4.3-changed-matrix-calc` to production.** T04_Payment_Processing (p99 1614ms) and T05_Order_Confirmation (p99 1458ms) breach the 500ms threshold by over 900ms. This would directly degrade checkout conversion in production.

### Short-term

3. **Review the intent of the matrix size change.** If variable matrix computation is required for new functionality, define the acceptable maximum matrix size and implement a validation guard. Matrix sizes appropriate for batch processing are not suitable for synchronous HTTP request paths.

4. **Add a CPU regression threshold to SLO checks.** The current CPU SLO is 70% (absolute mean) — the current run at 14.2% passes easily. Add an Adapt benchmark threshold (e.g., CPU < 8% mean on afterburner-fe) to catch CPU regressions earlier in the pipeline.

5. **Investigate the `/flaky` error rate increase** (T03 +388%): If the flakiness parameter did not change between baseline and current, the increase is statistical noise and should be accepted. If `flakiness=5` was intentionally increased from a lower baseline value, confirm this is the desired behaviour.

### Long-term

6. **Offload matrix computation to async workers.** CPU-intensive operations should not block synchronous HTTP request threads. The existing `execute-call-async` span infrastructure is already in use for other sub-requests — use it to parallelise or queue compute-heavy matrix operations.

7. **Add `matrix-size` as a tracked Perfana metric.** The span attribute `matrix-size` already exists in Tempo traces. Surfacing it as an Adapt-tracked metric would allow automatic detection of matrix size drift in future runs without requiring manual trace inspection.

8. **Establish a compute sub-request latency benchmark.** Add an absolute threshold check (e.g., sub-request avg < 50ms) in addition to the existing percentage-based Adapt comparison. This provides a signal even when the baseline itself is degraded.

---

*Report generated: 2026-05-17 | Sources: Perfana Adapt, Pyroscope hotspots (Perfana wrapper), Loki logs, Tempo traces (Perfana wrapper), Docker container metrics, JVM G1GC metrics, config diff*
