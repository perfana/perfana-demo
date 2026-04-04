---
testRunId: PerfanaWebshop-acc-loadTest-00009
system: PerfanaWebshop
environment: acc
workload: loadTest
release: 2.4.3-changed-matrix-calc
date: 2026-03-23
duration: 364s
result: FAIL
tags: [performance-report, jmeter, spring-boot-kubernetes, jfr, spanmetrics, docker]
baseline: PerfanaWebshop-acc-loadTest-00008
---

# Performance test report — PerfanaWebshop-acc-loadTest-00009

## Summary

| Field | Value |
|---|---|
| System | PerfanaWebshop |
| Environment | acc |
| Workload | loadTest |
| Release | `2.4.3-changed-matrix-calc` |
| Start time | 2026-03-23T19:51:38Z |
| Duration | 364s (planned 360s) |
| Completion | 100% |
| **Overall result** | **FAIL** |
| Adapt verdict | REGRESSION (38 regressions) |
| SLO checks passed | 7 / 14 |
| Annotations | Proxy Dev: make matrix calculation more variable |
| Tags | jmeter, spring-boot-kubernetes, jfr, spanmetrics, docker |

> Release `2.4.3-changed-matrix-calc` introduces severe CPU-bound computation regressions across all transaction flows, with sub-request response times increasing 200-1700%. The changed matrix calculation algorithm is the root cause, confirmed by cross-source causal chain: compute regressions -> CPU spike (+124%) -> GC pressure (+193%).

---

## Verdict

### Adapt regression analysis

| Metric | Count |
|---|---|
| Total regressions | 38 |
| Improvements | 1 |
| Differences | 266 |
| **Conclusion** | **REGRESSION** |

### SLO / requirements checks

| Dashboard | Metric | Result | Value | Requirement |
|---|---|---|---|---|
| Apdex SLO | T01_Homepage_Load | PASS | 1.000 | Apdex >= 0.85 |
| Apdex SLO | T02_Browse_Category | PASS | 1.000 | Apdex >= 0.85 |
| Apdex SLO | T03_Search_Products | FAIL | 0.750 | Apdex >= 0.85 |
| Apdex SLO | T04_View_Product_Details | PASS | 0.908 | Apdex >= 0.85 |
| Apdex SLO | T05_Apply_Filters | FAIL | 0.731 | Apdex >= 0.85 |
| Apdex SLO | T06_Compare_Products | FAIL | 0.744 | Apdex >= 0.85 |
| Apdex SLO | T07_Product_Assets | PASS | 1.000 | Apdex >= 0.85 |
| Apdex SLO | T01_Add_To_Cart | PASS | 1.000 | Apdex >= 0.85 |
| Apdex SLO | T02_User_Login | FAIL | 0.697 | Apdex >= 0.85 |
| Apdex SLO | T03_Shipping_Address | PASS | 0.943 | Apdex >= 0.85 |
| Apdex SLO | T04_Payment_Processing | FAIL | 0.708 | Apdex >= 0.85 |
| Apdex SLO | T05_Order_Confirmation | FAIL | 0.662 | Apdex >= 0.85 |
| Apdex SLO | T06_Post_Order_Recommendations | FAIL | 0.714 | Apdex >= 0.85 |
| Apdex SLO | T07_Order_Tracking_Assets | PASS | 0.939 | Apdex >= 0.85 |

---

## Transaction performance

### Response time table

| Transaction | Scenario | Avg (ms) | p95 (ms) | p99 (ms) | Threshold (ms) | Apdex | |
|---|---|---|---|---|---|---|---|
| T05_Order_Confirmation | Checkout | 885.84 | 1278.40 | 1326.56 | 753 | 0.662 | :x: |
| T02_User_Login | Checkout | 332.58 | 427.80 | 479.44 | 317 | 0.697 | :x: |
| T04_Payment_Processing | Checkout | 1094.41 | 1470.20 | 1544.44 | 1052 | 0.703 | :x: |
| T06_Post_Order_Recommendations | Checkout | 199.03 | 304.30 | 387.66 | 172 | 0.714 | :x: |
| T05_Apply_Filters | BrowseAndSearch | 95.85 | 167.20 | 318.18 | 84 | 0.731 | :x: |
| T06_Compare_Products | BrowseAndSearch | 283.15 | 409.90 | 565.06 | 261 | 0.744 | :x: |
| T03_Search_Products | BrowseAndSearch | 384.61 | 530.05 | 675.19 | 376 | 0.750 | :x: |
| T04_View_Product_Details | BrowseAndSearch | 480.34 | 662.25 | 884.76 | 480 | 0.908 | :white_check_mark: |
| T07_Order_Tracking_Assets | Checkout | 176.18 | 265.60 | 338.60 | 251 | 0.939 | :white_check_mark: |
| T03_Shipping_Address | Checkout | 413.06 | 443.50 | 454.26 | 433 | 0.943 | :white_check_mark: |
| T01_Homepage_Load | BrowseAndSearch | 281.51 | 316.00 | 317.24 | 614 | 1.000 | :white_check_mark: |
| T02_Browse_Category | BrowseAndSearch | 242.41 | 263.90 | 280.06 | 288 | 1.000 | :white_check_mark: |
| T01_Add_To_Cart | Checkout | 224.33 | 243.60 | 257.56 | 430 | 1.000 | :white_check_mark: |
| T07_Product_Assets | BrowseAndSearch | 98.38 | 148.10 | 162.34 | 166 | 1.000 | :white_check_mark: |

_:white_check_mark: Apdex >= 0.85 · :warning: Apdex 0.70-0.85 · :x: Apdex < 0.70_

### p99 tail overshoot (transactions where p99 > threshold)

| Transaction | p99 (ms) | Threshold (ms) | Overshoot | % over |
|---|---|---|---|---|
| T05_Order_Confirmation | 1326.56 | 753 | +573.56ms | +76.2% |
| T04_Payment_Processing | 1544.44 | 1052 | +492.44ms | +46.8% |
| T06_Compare_Products | 565.06 | 261 | +304.06ms | +116.5% |
| T04_View_Product_Details | 884.76 | 480 | +404.76ms | +84.3% |
| T03_Search_Products | 675.19 | 376 | +299.19ms | +79.6% |
| T05_Apply_Filters | 318.18 | 84 | +234.18ms | +278.8% |
| T06_Post_Order_Recommendations | 387.66 | 172 | +215.66ms | +125.4% |
| T02_User_Login | 479.44 | 317 | +162.44ms | +51.2% |
| T07_Order_Tracking_Assets | 338.60 | 251 | +87.60ms | +34.9% |
| T03_Shipping_Address | 454.26 | 433 | +21.26ms | +4.9% |

### Top 5 by impact score

| Rank | Transaction | Avg RT (ms) | Count | Impact | Apdex |
|---|---|---|---|---|---|
| 1 | T04_Payment_Processing | 1094.41 | 37 | 40493 | 0.703 |
| 2 | T05_Order_Confirmation | 885.84 | 37 | 32776 | 0.662 |
| 3 | T04_View_Product_Details | 480.34 | 38 | 18253 | 0.908 |
| 4 | T03_Search_Products | 384.61 | 38 | 14615 | 0.750 |
| 5 | T03_Shipping_Address | 413.06 | 35 | 14457 | 0.943 |

---

## Regression analysis vs baseline

> Baseline: `PerfanaWebshop-acc-loadTest-00008` — 2.4.3-good-baseline (2026-03-23)
> Config changes: 4 · Unchanged: 22

### Config changes

| Key | Baseline | Current |
|---|---|---|
| `https://github.com/perfana/perfana-demo` | 4e2db5f | 26361d2 |
| `testContext.annotations` | Proxy Dev: make cpu more efficient | Proxy Dev: make matrix calculation more variable |
| `testContext.version` | 2.4.3-good-baseline | 2.4.3-changed-matrix-calc |

### Regressions by classification

#### Computation kernel (10 regressions)

**Hypothesis:** The code change in release `2.4.3-changed-matrix-calc` introduced a more expensive matrix calculation algorithm that runs on the request thread. The annotation "make matrix calculation more variable" confirms the change was intentional. Every compute sub-request (`_compute`, `_processing`, `_ranking`, `_engine`, `_hash`) shows 270-1700% regression.

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| T04_Payment_Processing.payment_fraud_check | Perf test Checkout | 7.2ms | 133.1ms | +1742.0% |
| T04_Payment_Processing.payment_card_encryption | Perf test Checkout | 6.6ms | 101.0ms | +1426.7% |
| T03_Search_Products.search_query_processing | Perf test BrowseAndSearch | 5.6ms | 78.5ms | +1308.2% |
| T02_User_Login.login_credential_hash | Perf test Checkout | 4.7ms | 52.0ms | +1012.3% |
| T06_Post_Order_Recommendations.recommendations_ml_engine | Perf test Checkout | 6.2ms | 55.1ms | +784.5% |
| T03_Shipping_Address.shipping_cost_compute | Perf test Checkout | 2.8ms | 19.7ms | +603.1% |
| T03_Search_Products.search_results_ranking | Perf test BrowseAndSearch | 5.4ms | 34.6ms | +539.4% |
| T01_Homepage_Load.homepage_recommendations_compute | Perf test BrowseAndSearch | 3.4ms | 20.8ms | +515.2% |

#### Transaction latency (14 regressions)

**Hypothesis:** Downstream consequence of the slow compute sub-requests. Each transaction chains multiple compute calls — as each sub-request slows by 5-15x, the cumulative effect exceeds Apdex thresholds. The worst affected transactions (T04_Payment_Processing, T05_Order_Confirmation) contain the most compute-heavy sub-requests.

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| T05_Order_Confirmation (Apdex) | Perf test Checkout | 0.946 | 0.662 | -30.0% |
| T04_Payment_Processing (Apdex) | Perf test Checkout | 1.000 | 0.703 | -29.7% |
| T02_User_Login (Apdex) | Perf test Checkout | 1.000 | 0.697 | -30.3% |
| T06_Post_Order_Recommendations (Apdex) | Perf test Checkout | 0.986 | 0.714 | -27.5% |
| T03_Search_Products (Apdex) | Perf test BrowseAndSearch | 1.000 | 0.750 | -25.0% |
| T05_Apply_Filters (Apdex) | Perf test BrowseAndSearch | 0.950 | 0.731 | -23.1% |
| T06_Compare_Products (Apdex) | Perf test BrowseAndSearch | 0.950 | 0.744 | -21.7% |
| T06_Post_Order_Recommendations (RT) | Perf test Checkout | 149.2ms | 199.0ms | +33.4% |

#### Request latency (10 regressions)

**Hypothesis:** Sub-requests that are not purely compute-bound but call downstream services also regressed. The CPU contention from the matrix calculation change causes thread starvation, which increases response times for all sub-requests including I/O-bound ones like `order_confirmation_pdf_gen` (+1696.8%) and `filter_facets_recalculate` (+877.9%).

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| T05_Order_Confirmation.order_confirmation_pdf_gen | Perf test Checkout | 8.5ms | 152.0ms | +1696.8% |
| T05_Apply_Filters.filter_facets_recalculate | Perf test BrowseAndSearch | 3.3ms | 32.0ms | +877.9% |
| T04_View_Product_Details.product_reviews_aggregate | Perf test BrowseAndSearch | 2.8ms | 16.7ms | +504.4% |
| T02_User_Login.login_jwt_generation | Perf test Checkout | 3.2ms | 17.8ms | +447.9% |
| T03_Shipping_Address.shipping_address_validation | Perf test Checkout | 2.5ms | 9.4ms | +274.9% |
| T01_Add_To_Cart.cart_price_calculation | Perf test Checkout | 3.1ms | 11.3ms | +265.2% |
| T01_Add_To_Cart.cart_product_validation | Perf test Checkout | 3.2ms | 5.8ms | +79.1% |
| T04_View_Product_Details.product_info_db_lookup | Perf test BrowseAndSearch | 52.8ms | 77.9ms | +47.5% |

#### JVM memory / GC (1 regression)

**Hypothesis:** The CPU-intensive algorithm creates more short-lived intermediate objects, increasing young generation allocation pressure. Minor GC collections due to Allocation Failure nearly tripled (+193.3%), consistent with a computation-heavy code change. No major GC events occurred during the test, so this is secondary pressure, not yet critical.

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| `(Allocation Failure)` | JVM memory management G1GC afterburner-fe | 0.109 ops | 0.320 ops | +193.3% |

#### Container resources (1 regression)

**Hypothesis:** Secondary to the CPU-intensive computation — the container CPU budget for afterburner-fe is consumed by the new matrix calculation. Average CPU usage jumped from 5.9% to 13.3%, with peaks at 30.9%. At higher load levels, this risks CPU throttling.

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| `Usage` | Docker container metrics perfana-demo-afterburner-fe-1 | 5.9% | 13.3% | +124.4% |

#### DB connection pool (1 regression)

**Hypothesis:** Cascading effect of slower requests holding database connections open longer. Active connections on employee-db-pool increased by 25%, but remain far from the pool maximum (peak 1 of ~7 available). This is not the root cause — it is a consequence of increased request latency.

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| `employee-db-pool` | Hikari Connection Pool afterburner-be | 0.04 | 0.05 | +25.0% |

#### Error rates (2 regressions)

**Hypothesis:** Error rate increase on T07_Product_Assets is from the `/flaky` endpoint, which is a chaos test fixture. The error rate regression (+200%) is caused by the flaky endpoint firing more often under the higher load induced by the latency regression. Not a real application error.

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| T07_Product_Assets (error rate) | Perf test BrowseAndSearch | 2.56% | 7.69% | +200.0% |
| T07_Product_Assets.product_availability_check (error rate) | Perf test BrowseAndSearch | 2.56% | 7.69% | +200.0% |

### Improvements (preserve in any rollback)

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| `difference_cpuThrottledTime` | JFR Exporter afterburner-fe | 16008.88ns | 0ns | -100.0% |

---

## Error analysis

| Metric | Value |
|---|---|
| Total requests | 2407 |
| Total errors | 4 |
| Overall error rate | 0.17% |
| Unique HTTP error codes | 1 |
| Transactions with errors | 2 |

### Errors by status code

| Code | Count | Avg RT (ms) | Min RT (ms) | Max RT (ms) |
|---|---|---|---|---|
| 500 | 4 | 118 | 76 | 233 |

### Errors by transaction

| Transaction | Sampler | URL | Code | Count | Classification |
|---|---|---|---|---|---|
| T07_Product_Assets | product_availability_check | `http://afterburner-fe:8080/flaky?flakiness=3&maxRandomDelay=100` | 500 | 3 | Flaky fixture |
| T04_Payment_Processing | payment_gateway_auth | `http://afterburner-fe:8080/flaky?maxRandomDelay=300&flakiness=3` | 500 | 1 | Flaky fixture |

> All errors originate from `/flaky` endpoints (Afterburner chaos fixture).
> These are **not real application errors** — classify as test infrastructure noise.
> Error rate regressions in Adapt are caused by the flaky endpoint firing more often
> under the higher load induced by the latency regression.

---

## Cross-source investigation

> **Data sources:** Grafana :white_check_mark: · Tempo :white_check_mark: · Pyroscope :white_check_mark: · Dynatrace :x:
> **Confidence:** High

### Distributed traces

**Slowest traces:** No slow traces found in test run time window.

_Tempo was connected but returned no traces matching the test run. This may be due to trace sampling configuration or short test duration. Trace-level span analysis was not possible._

**Error traces:** No error traces found in test run time window.

### CPU profiling (Pyroscope)

_Pyroscope data unavailable for service afterburner-fe — the hotspot and flamegraph API calls returned internal server errors. CPU profiling analysis was skipped. This is likely a data collection timing issue given the test run's "2 failed collection ranges across 2 sources" validation warning._

### Dashboard snapshots

**Docker container metrics perfana-demo-afterburner-fe-1:**

| Panel | Metric | Avg | Min | Max | Last |
|---|---|---|---|---|---|
| CPU | Usage | 13.26% | 4.65% | 30.93% | 8.22% |
| Memory | Usage | 42.68% | 40.63% | 43.96% | 43.96% |
| IO | IO service recursive read | 7.99MB | 7.87MB | 8.10MB | 8.10MB |

**JVM memory management G1GC afterburner-fe:**

| Panel | Metric | Avg | Min | Max | Last |
|---|---|---|---|---|---|
| Average JVM Heap % used | JVM Heap % used | 69.76% | 57.57% | 82.10% | 65.59% |
| Collections end of minor GC | (Allocation Failure) | 0.320 ops/s | 0.255 | 0.364 | 0.327 |
| Average Pause Durations minor GC | Allocation Failure | 3.41ms | 2.56ms | 5.86ms | 3.22ms |
| Maximum Pause Durations minor GC | Allocation Failure | 19.10ms | 5.00ms | 61.00ms | 8.00ms |
| Old gen memory pool increase | promoted | 138.8KB/s | 0 | 501.2KB/s | 199.9KB/s |
| Collections end of major GC | (Allocation Failure) | 0 | 0 | 0 | 0 |
| Average Tenured Gen in use | Tenured Gen | 84.7MB | 74.1MB | 94.6MB | 94.6MB |

**Hikari Connection Pool afterburner-be:**

| Panel | Metric | Avg | Min | Max | Last |
|---|---|---|---|---|---|
| Active connections | employee-db-pool | 0.05 | 0 | 1 | 0 |
| Idle connections | employee-db-pool | 4.30 | 3 | 7 | 4 |
| Pending connections | employee-db-pool | 0 | 0 | 0 | 0 |
| Timeout total time | employee-db-pool | 0 | 0 | 0 | 0 |
| Acquire time | employee-db-pool | 0.197ms | 0.088ms | 0.332ms | 0.088ms |
| Queries / second | employee-db-pool | 1.75 | 0.80 | 2.40 | 2.00 |

### Investigation gaps

- **Tempo:** Connected but returned no traces for the test run time window — trace-level span analysis was skipped
- **Pyroscope:** Connected but returned HTTP 500 errors for both hotspot and flamegraph queries — CPU profiling analysis was skipped
- **Dynatrace:** Not connected — infrastructure problem detection was not available

---

## Root cause & recommendations

### Root cause (confidence: High)

The release `2.4.3-changed-matrix-calc` changed the matrix calculation algorithm in the afterburner-fe service, as confirmed by the annotation "Proxy Dev: make matrix calculation more variable" and the version change from `2.4.3-good-baseline` to `2.4.3-changed-matrix-calc`. The git commit changed from `4e2db5f` to `26361d2`.

This change introduced significantly more CPU-intensive computation across all request-handling code paths. The evidence is unambiguous: every compute sub-request (`_compute`, `_processing`, `_ranking`, `_engine`, `_hash`) regressed by 270-1742%, while the previous baseline with annotation "make cpu more efficient" passed all SLOs. The regressions are not isolated to a single transaction — they span all 14 transactions across both the BrowseAndSearch and Checkout scenarios, indicating the matrix calculation is a shared computation kernel used throughout the application.

The Adapt causal chain analysis confirms the cascade with high confidence: compute sub-request regressions (performance test metrics) caused a CPU spike on the afterburner-fe container (Docker metrics: average CPU +124%, peaks at 30.9%), which in turn increased GC pressure (minor GC Allocation Failure collections +193.3%). The connection pool shows a minor secondary effect (+25% active connections) but remains healthy with no pending connections or timeouts — this is a consequence, not a cause.

The single most likely root cause is the **changed matrix calculation algorithm** in commit `26361d2`. The new algorithm is approximately 10-15x more CPU-expensive than the previous implementation, causing all downstream latency, Apdex, and resource regressions observed.

### Evidence chain

| Source | Finding | Supports hypothesis? |
|---|---|---|
| Adapt (perf test) | 10 compute sub-requests regressed 270-1742% | Yes :white_check_mark: |
| Adapt (transaction) | 8 transactions show Apdex drops of 21-30% | Yes :white_check_mark: |
| Config diff | Version changed to `changed-matrix-calc`, annotation says "make matrix calculation more variable" | Yes :white_check_mark: |
| Docker container metrics | CPU usage +124% (avg 5.9% -> 13.3%, peak 30.9%) | Yes :white_check_mark: |
| JVM GC metrics | Minor GC Allocation Failure +193%, heap usage avg 70% | Yes :white_check_mark: |
| Hikari connection pool | Active connections +25% but far from max, no timeouts | Partial :warning: |
| Adapt causal chains | 3 high-confidence chains all pointing to compute -> CPU -> GC | Yes :white_check_mark: |
| Error analysis | All 4 errors on /flaky endpoints — not related to regression | Yes :white_check_mark: |
| Tempo traces | No traces found — could not confirm at span level | _Gap_ |
| Pyroscope flamegraph | API error — could not confirm hot methods | _Gap_ |

### Recommendations

  1. **Revert commit `26361d2`** or fix the matrix calculation algorithm. The "more variable" computation is 10-15x more expensive than the baseline. If variability is required, consider an async or cached approach that does not block the request thread.

1. **Profile the matrix calculation with Pyroscope** once the data collection issue is resolved. Run `process_cpu:cpu:nanoseconds` profiling on `afterburner-fe` during a load test to identify the exact hot methods in the new algorithm. The current test's Pyroscope data was unavailable due to collection failures.

2. **Investigate the highest-impact sub-requests first:** `payment_fraud_check` (+1742%), `payment_card_encryption` (+1426%), and `search_query_processing` (+1308%). These three sub-requests alone account for the majority of the user-facing latency in T04_Payment_Processing and T03_Search_Products.

3. **Add CPU budget alerting** for the afterburner-fe container. The current test peaked at 30.9% CPU — under production load levels this could trigger container throttling. Set an alert at 60% sustained CPU usage.

4. **Fix Tempo and Pyroscope data collection** — the test run reported "2 failed collection ranges across 2 sources". Ensure trace sampling and continuous profiling are reliably capturing data for the full test duration to enable deeper investigation in future runs.

---

## Run trend (last 5 runs)

| Run | Date | Release | Result | Adapt |
|---|---|---|---|---|
| `PerfanaWebshop-acc-loadTest-00009` | 2026-03-23 | 2.4.3-changed-matrix-calc | FAIL | REGRESSION |
| `PerfanaWebshop-acc-loadTest-00008` | 2026-03-23 | 2.4.3-good-baseline | PASS | NO_BASELINES_FOUND |
| `PerfanaWebshop-acc-loadTest-00007` | 2026-03-23 | 2.4.3-good-baseline | FAIL | REGRESSION |
| `PerfanaWebshop-acc-loadTest-00006` | 2026-03-23 | 2.4.3-good-baseline | _N/A_ | _N/A_ |
| `PerfanaWebshop-acc-loadTest-00005` | 2026-03-11 | 2.4.3-changed-matrix-calc | FAIL | REGRESSION |

---

## Links

- [fooba](http://foo)
- [foobar](http://google.com)
- [CI build](http://nu.nl)

---

_Report generated 2026-03-24 by Claude Code · Perfana report skill v2.0 (with cross-source investigation)_
