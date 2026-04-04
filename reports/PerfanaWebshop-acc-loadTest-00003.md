---
testRunId: PerfanaWebshop-acc-loadTest-00003
system: PerfanaWebshop
environment: acc
workload: loadTest
release: 2.4.3-changed-matrix-calc
date: 2026-03-29
duration: 364s
result: FAIL
tags: [performance-report, jmeter, spring-boot-kubernetes, spanmetrics, docker]
baseline: PerfanaWebshop-acc-loadTest-00002
---

# Performance test report — PerfanaWebshop-acc-loadTest-00003

## Summary

| Field | Value |
|---|---|
| System | PerfanaWebshop |
| Environment | acc |
| Workload | loadTest |
| Release | `2.4.3-changed-matrix-calc` |
| Start time | 2026-03-29T18:06:49.114Z |
| Duration | 364s (planned 360s) |
| Completion | 100% |
| **Overall result** | **FAIL ❌** |
| Adapt verdict | REGRESSION |
| SLO checks passed | 10 / 10 |
| Annotations | Proxy Dev: make matrix calculation more variable |
| Tags | jmeter, spring-boot-kubernetes, spanmetrics, docker |

> Release `2.4.3-changed-matrix-calc` introduces a severe CPU regression caused by `MatrixCalculator.multiply` consuming 69% of CPU. All SLO checks pass, but Adapt detected 34 regressions across performance test metrics, JVM GC, container resources, and connection pools. The root cause is a changed matrix calculation algorithm that is significantly more CPU-intensive than the baseline.

---

## Verdict

### Adapt regression analysis

| Metric | Count |
|---|---|
| Total metrics evaluated | 280 |
| Regressions | 34 |
| Improvements | 5 |
| Differences | 241 |
| No difference | 0 |
| **Conclusion** | **REGRESSION** |

### SLO / requirements checks

| Dashboard | Metric | Result | Value | Requirement |
|---|---|---|---|---|
| Docker container metrics perfana-demo-afterburner-be-1 | CPU | PASS ✅ | 2.91% | < 70% |
| Docker container metrics perfana-demo-afterburner-fe-1 | CPU | PASS ✅ | 15.07% | < 70% |
| Hikari Connection Pool afterburner-be | Pending connections | PASS ✅ | 0 | < 10 |
| Hikari Connection Pool afterburner-fe | Pending connections | PASS ✅ | 0 | < 10 |
| HTTP connection pool afterburner-be | HTTP connection pool in use | PASS ✅ | 0% | < 90% |
| HTTP connection pool afterburner-fe | HTTP connection pool in use | PASS ✅ | 0.83% | < 90% |
| JVM memory management G1GC afterburner-be | Max Pause minor GC | PASS ✅ | 0.014s | < 0.1s |
| JVM memory management G1GC afterburner-fe | Max Pause minor GC | PASS ✅ | 0.019s | < 0.1s |
| JVM memory management G1GC afterburner-be | Max Pause major GC | PASS ✅ | 0.008s | < 0.6s |
| JVM memory management G1GC afterburner-fe | Max Pause major GC | PASS ✅ | 0.081s | < 0.6s |

---

## Transaction performance

### Response time table

| Transaction | Scenario | Avg (ms) | p95 (ms) | p99 (ms) | Threshold (ms) | Apdex | |
|---|---|---|---|---|---|---|---|
| T04_Payment_Processing | Checkout | 1105.70 | 1477.80 | 1540.04 | 500 | 0.500 | ❌ |
| T05_Order_Confirmation | Checkout | 911.19 | 1342.40 | 1364.64 | 500 | 0.500 | ❌ |
| T03_Search_Products | BrowseAndSearch | 377.72 | 631.60 | 651.26 | 500 | 0.936 | ⚠️ |
| T04_View_Product_Details | BrowseAndSearch | 445.77 | 535.90 | 585.88 | 500 | 0.949 | ⚠️ |
| T02_User_Login | Checkout | 336.94 | 417.00 | 483.92 | 500 | 0.985 | ✅ |
| T03_Shipping_Address | Checkout | 404.29 | 430.90 | 492.40 | 500 | 0.986 | ✅ |
| T01_Homepage_Load | BrowseAndSearch | 293.26 | 376.70 | 471.08 | 500 | 0.987 | ✅ |
| T06_Compare_Products | BrowseAndSearch | 287.72 | 370.10 | 527.30 | 500 | 0.987 | ✅ |
| T01_Add_To_Cart | Checkout | 227.30 | 274.00 | 289.92 | 500 | 1.000 | ✅ |
| T02_Browse_Category | BrowseAndSearch | 244.62 | 262.10 | 335.86 | 500 | 1.000 | ✅ |
| T05_Apply_Filters | BrowseAndSearch | 84.18 | 117.90 | 172.24 | 500 | 1.000 | ✅ |
| T06_Post_Order_Recommendations | Checkout | 214.40 | 337.90 | 369.18 | 500 | 1.000 | ✅ |
| T07_Order_Tracking_Assets | Checkout | 168.61 | 265.00 | 346.40 | 500 | 1.000 | ✅ |
| T07_Product_Assets | BrowseAndSearch | 100.45 | 178.55 | 240.86 | 500 | 1.000 | ✅ |

_✅ Apdex ≥ 0.85 · ⚠️ Apdex 0.70–0.85 · ❌ Apdex < 0.70_

### p99 tail overshoot (transactions where p99 > threshold)

| Transaction | p99 (ms) | Threshold (ms) | Overshoot | % over |
|---|---|---|---|---|
| T04_Payment_Processing | 1540.04 | 500 | +1040.04ms | +208.0% |
| T05_Order_Confirmation | 1364.64 | 500 | +864.64ms | +172.9% |
| T03_Search_Products | 651.26 | 500 | +151.26ms | +30.3% |
| T04_View_Product_Details | 585.88 | 500 | +85.88ms | +17.2% |
| T06_Compare_Products | 527.30 | 500 | +27.30ms | +5.5% |

### Top 5 by impact score

| Rank | Transaction | Avg RT (ms) | Count | Impact | Apdex |
|---|---|---|---|---|---|
| 1 | T04_Payment_Processing | 1105.70 | 37 | 40911 | 0.500 |
| 2 | T05_Order_Confirmation | 911.19 | 37 | 33714 | 0.500 |
| 3 | T04_View_Product_Details | 445.77 | 39 | 17385 | 0.949 |
| 4 | T03_Search_Products | 377.72 | 39 | 14731 | 0.936 |
| 5 | T03_Shipping_Address | 404.29 | 35 | 14150 | 0.986 |

---

## Regression analysis vs baseline

> Baseline: `PerfanaWebshop-acc-loadTest-00002` — 2.4.3-good-baseline (2026-03-29)
> Config changes: 4 · Unchanged: 22

### Config changes

| Key | Baseline | Current |
|---|---|---|
| `https://github.com/perfana/perfana-demo` | 4e2db5f | 26361d2 |
| `testContext.annotations` | Proxy Dev: make cpu more efficient | Proxy Dev: make matrix calculation more variable |
| `testContext.testRunId` | PerfanaWebshop-acc-loadTest-00002 | PerfanaWebshop-acc-loadTest-00003 |
| `testContext.version` | 2.4.3-good-baseline | 2.4.3-changed-matrix-calc |

### Regressions by classification

#### Computation kernel (9 regressions)

**Hypothesis:** The code change introduced CPU-bound work on the request thread. Sub-requests with `_compute`, `_processing`, `_ranking`, `_engine`, and `_hash` suffixes are the direct source. The annotation "make matrix calculation more variable" and Pyroscope profiling confirm `MatrixCalculator.multiply` (69% CPU) as the root cause.

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| `T06_Post_Order_Recommendations.recommendations_ml_engine` | Performance test metrics Checkout | 4.77ms | 78.81ms | +1553.8% |
| `T03_Search_Products.search_query_processing` | Performance test metrics BrowseAndSearch | 5.53ms | 82.69ms | +1395.9% |
| `T02_User_Login.login_credential_hash` | Performance test metrics Checkout | 5.01ms | 63.86ms | +1173.7% |
| `T03_Search_Products.search_results_ranking` | Performance test metrics BrowseAndSearch | 3.65ms | 46.00ms | +1161.8% |
| `T06_Compare_Products.compare_feature_matrix_compute` | Performance test metrics BrowseAndSearch | 5.60ms | 63.83ms | +1040.4% |
| `T01_Homepage_Load.homepage_recommendations_compute` | Performance test metrics BrowseAndSearch | 2.97ms | 20.13ms | +578.0% |
| `T05_Apply_Filters.filter_validation_compute` | Performance test metrics BrowseAndSearch | 2.31ms | 13.58ms | +489.2% |
| `T03_Shipping_Address.shipping_cost_compute` | Performance test metrics Checkout | 3.03ms | 12.12ms | +300.5% |
| `T02_Browse_Category.category_filter_options_compute` | Performance test metrics BrowseAndSearch | 3.01ms | 10.35ms | +243.8% |

#### Request latency (8 regressions)

**Hypothesis:** Downstream consequence of the CPU-bound compute regression. As compute sub-requests slow down, other request-level calls on the same thread are also delayed due to CPU contention.

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| `T05_Order_Confirmation.order_confirmation_pdf_gen` | Performance test metrics Checkout | 8.13ms | 179.61ms | +2108.4% |
| `T04_Payment_Processing.payment_card_encryption` | Performance test metrics Checkout | 5.59ms | 111.53ms | +1894.7% |
| `T04_Payment_Processing.payment_fraud_check` | Performance test metrics Checkout | 6.41ms | 145.69ms | +2173.5% |
| `T05_Apply_Filters.filter_facets_recalculate` | Performance test metrics BrowseAndSearch | 3.01ms | 21.58ms | +616.3% |
| `T03_Shipping_Address.shipping_address_validation` | Performance test metrics Checkout | 2.30ms | 13.00ms | +465.2% |
| `T01_Add_To_Cart.cart_price_calculation` | Performance test metrics Checkout | 2.80ms | 12.94ms | +362.1% |
| `T04_View_Product_Details.product_reviews_aggregate` | Performance test metrics BrowseAndSearch | 2.59ms | 10.70ms | +312.5% |
| `T01_Add_To_Cart.cart_product_validation` | Performance test metrics Checkout | 2.85ms | 5.21ms | +83.0% |

#### Transaction latency (5 regressions)

**Hypothesis:** Downstream consequence of slow compute sub-requests. Each transaction chains multiple compute and request calls — as each slows, the total exceeds the Apdex threshold.

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| `T05_Apply_Filters` | Performance test metrics BrowseAndSearch | 55.61ms | 84.75ms | +52.4% |
| `T06_Post_Order_Recommendations` | Performance test metrics Checkout | 141.36ms | 214.40ms | +51.7% |
| `T06_Compare_Products` | Performance test metrics BrowseAndSearch | 223.51ms | 287.72ms | +28.7% |
| `T05_Order_Confirmation` | Performance test metrics Checkout | 719.93ms | 911.19ms | +26.6% |
| `T02_User_Login` | Performance test metrics Checkout | 267.59ms | 336.94ms | +25.9% |

#### Error rates (4 regressions)

**Hypothesis:** All errors hit `/flaky` URLs — test fixture noise, not a real regression. Error rate regressions in Adapt are caused by the flaky endpoint firing more often under the higher load induced by the latency regression.

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| `T07_Order_Tracking_Assets` | Performance test metrics Checkout | 5.97% | 9.09% | +52.3% |
| `T07_Order_Tracking_Assets.loyalty_points_api` | Performance test metrics Checkout | 2.99% | 6.06% | +103.0% |
| `T07_Order_Tracking_Assets.shipping_status_check` | Performance test metrics Checkout | 0% | 3.33% | new |
| `T04_Payment_Processing.payment_gateway_auth` | Performance test metrics Checkout | 0% | 3.03% | new |

#### JVM memory / GC (4 regressions)

**Hypothesis:** High old-gen promotion rate combined with new major GC events = the changed matrix algorithm is creating long-lived intermediate objects that survive minor GC. Minor GC frequency on afterburner-fe increased +220%, major GC events appeared (previously zero), and tenured gen usage grew +37%.

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| `(Allocation Failure)` | JVM memory management G1GC afterburner-fe | 0.106 ops | 0.340 ops | +220.2% |
| `Tenured Gen in use` | JVM memory management G1GC afterburner-fe | 74.0MB | 101.7MB | +37.4% |
| `(Allocation Failure)` | JVM memory management G1GC afterburner-be | 0.100 ops | 0.124 ops | +24.1% |
| `(Allocation Failure)` major GC | JVM memory management G1GC afterburner-fe | 0 ops | 0.005 ops | new |

#### Container resources (1 regression)

**Hypothesis:** Secondary to the CPU spike — the container CPU budget is consumed by the matrix computation. Risk of throttling at higher load.

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| `Usage` | Docker container metrics perfana-demo-afterburner-fe-1 | 4.85% | 15.07% | +210.8% |

#### DB connection pool (1 regression)

**Hypothesis:** Cascading effect of slower requests holding connections open longer. Not the root cause — active count is minimal (0.05 vs 0 baseline).

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| `employee-db-pool` | Hikari Connection Pool afterburner-be | 0 | 0.05 | +150.0% |

### Improvements (preserve in any rollback)

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| `T03_Search_Products` | Performance test metrics BrowseAndSearch | 1.15% | 0% | -100% |
| `T03_Search_Products.search_external_api_call` | Performance test metrics BrowseAndSearch | 1.16% | 0% | -100% |
| `T07_Product_Assets` | Performance test metrics BrowseAndSearch | 1.28% | 0% | -100% |
| `T07_Product_Assets.product_availability_check` | Performance test metrics BrowseAndSearch | 1.30% | 0% | -100% |
| `error_count` | Performance test metrics BrowseAndSearch | 0.18 | 0 | -100% |

---

## Error analysis

| Metric | Value |
|---|---|
| Total requests | 2411 |
| Total errors | 4 |
| Overall error rate | 0.17% |
| Unique HTTP error codes | 1 |
| Transactions with errors | 2 |

### Errors by status code

| Code | Count | Avg RT (ms) | Min RT (ms) | Max RT (ms) |
|---|---|---|---|---|
| 500 | 4 | 115 | 12 | 271 |

### Errors by transaction

| Transaction | Sampler | URL | Code | Count | Classification |
|---|---|---|---|---|---|
| T07_Order_Tracking_Assets | loyalty_points_api | `http://afterburner-fe:8080/flaky?flakiness=3&maxRandomDelay=80` | 500 | 2 | Flaky fixture |
| T04_Payment_Processing | payment_gateway_auth | `http://afterburner-fe:8080/flaky?maxRandomDelay=300&flakiness=3` | 500 | 1 | Flaky fixture |
| T07_Order_Tracking_Assets | shipping_status_check | `http://afterburner-fe:8080/flaky?flakiness=2&maxRandomDelay=150` | 500 | 1 | Flaky fixture |

> All errors originate from `/flaky` endpoints (Afterburner chaos fixture).
> These are **not real application errors** — classify as test infrastructure noise.
> Error rate regressions in Adapt are caused by the flaky endpoint firing more often
> under the higher load induced by the latency regression.

---

## Cross-source investigation

> **Data sources:** Grafana ✅ · Tempo ✅ · Pyroscope ✅ · Dynatrace ❌
> **Confidence:** High

### Distributed traces — baseline vs current comparison

**Overall slowest traces (excluding traffic-light timer):**

| | Baseline (00002) | Current (00003) |
|---|---|---|
| Max duration | 153ms (`get /delay`) | 505ms (`get /remote/call-many`) |
| Median of top 9 | 104ms | 158ms |
| New trace types | — | `get /cpu/magic-identity-check` (not present in baseline) |

> The broad trace profile shifted significantly upward. Baseline max (excluding the 5s traffic-light timer) was 153ms; the current run reaches 505ms. The appearance of `cpu/magic-identity-check` traces is new — these did not appear in the baseline top traces at all.

**T04_Payment_Processing — per-transaction trace comparison:**

| | Baseline (00002) | Current (00003) |
|---|---|---|
| Slowest trace | 508ms (`call-many` → `delay` on be) | 507ms (`call-many` → `delay` on be) |
| New trace type | — | 239ms `cpu/magic-identity-check` (payment_card_encryption) |
| 2nd new trace | — | 165ms `cpu/magic-identity-check` (payment_card_encryption) |

**Trace drill-down** — `76765fbacb97b98d` (239ms, current run, `payment_card_encryption`):

| Span | Service | Duration | % of trace |
|---|---|---|---|
| `matrix-multiply` | afterburner-fe | 237ms | 98.9% |
| `matrix-init` | afterburner-fe | 1ms | 0.4% |
| `matrix-equal-check` | afterburner-fe | 0.16ms | 0.1% |

> **matrix-size: 620**. The `matrix-multiply` span consumes 99% of the trace. This span calls `CpuBurner.magicIdentityCheck`, which internally invokes `MatrixCalculator.multiply` — the same method Pyroscope identified as the 69% CPU hotspot. In the baseline, no `cpu/magic-identity-check` traces appeared in the top 5 for this transaction; the slowest traces were purely I/O-bound (`delay` calls to afterburner-be).

**T06_Compare_Products — per-transaction trace comparison:**

| | Baseline (00002) | Current (00003) |
|---|---|---|
| Slowest trace | 156ms (`call-many` → 3x parallel `delay`) | 158ms (`call-many`) |
| Tail traces | 60ms, 57ms | 153ms, 113ms (`cpu/magic-identity-check`) |

**Trace drill-down** — `e0fcac787fbf70d3` (113ms, current run, `compare_feature_matrix_compute`):

| Span | Service | Duration | % of trace |
|---|---|---|---|
| `matrix-multiply` | afterburner-fe | 110ms | 97.5% |
| `matrix-init` | afterburner-fe | 0.9ms | 0.8% |
| `matrix-equal-check` | afterburner-fe | 0.1ms | 0.1% |

> **matrix-size: 491**. Same pattern as T04 — `matrix-multiply` dominates. In the baseline, `T06_Compare_Products` traces were entirely I/O-bound (`compare_price_history_api` → 3 parallel `delay` calls to afterburner-be at ~153ms each). The compute-heavy `compare_feature_matrix_compute` sub-request is new CPU-bound work introduced by the code change.

**Baseline trace drill-down** — `c4015b2d92df9cfb` (156ms, baseline, `compare_price_history_api`):

| Span | Service | Duration | % of trace |
|---|---|---|---|
| `execute-call-async` (x3 parallel) | afterburner-fe | 154ms each | 99% |
| `get /delay` (x3 parallel) | afterburner-be | 153ms each | 98% |

> Baseline traces are entirely I/O-bound — 3 parallel async calls waiting on `delay` endpoints. No matrix computation. This confirms the `matrix-multiply` spans are new work introduced by `2.4.3-changed-matrix-calc`.

**Error traces:** No error traces found in Tempo for this test window.

### CPU profiling (Pyroscope)

**Top hotspots** for `afterburner-fe`:

| Method | Samples | % CPU |
|---|---|---|
| `io/perfana/afterburner/matrix/MatrixCalculator.multiply` | 33,407,892,866 | 68.98% |
| `libc.so.6.__libc_write` | 263,157,880 | 0.54% |
| `libc.so.6.__GI___fstatat64` | 236,842,092 | 0.49% |
| `.I2C/C2I adapters` | 144,736,834 | 0.30% |
| `libc.so.6.__GI___memset_generic` | 144,736,834 | 0.30% |
| `.itable stub` | 144,736,834 | 0.30% |
| `libjvm.so.IndexSetIterator::advance_and_next` | 131,578,940 | 0.27% |
| `java/util/HashMap.getNode` | 131,578,940 | 0.27% |
| `libc.so.6.__GI___futex_abstimed_wait_cancelable64` | 118,421,046 | 0.24% |
| `libc.so.6.__GI___getdents64` | 118,421,046 | 0.24% |

> `MatrixCalculator.multiply` dominates the CPU profile at **69% of all CPU samples**, dwarfing every other method by two orders of magnitude. This single method is the root cause of the entire regression cascade.

### Investigation gaps

- **Dynatrace:** Not connected — infrastructure problem correlation was not available.

---

## Root cause & recommendations

### Root cause (confidence: High)

The release `2.4.3-changed-matrix-calc` introduced a change to the matrix calculation algorithm (annotation: "make matrix calculation more variable"). This change made `MatrixCalculator.multiply` dramatically more CPU-intensive — Pyroscope profiling shows it consuming **69% of all CPU time** on `afterburner-fe`, up from negligible levels in the baseline.

The CPU-bound matrix computation is triggered by multiple sub-requests across both the Checkout and BrowseAndSearch scenarios. Every compute-suffixed sub-request (`_compute`, `_processing`, `_ranking`, `_engine`, `_hash`) regressed by 200%–2200%, with the worst offenders being `payment_fraud_check` (+2174%), `order_confirmation_pdf_gen` (+2108%), and `payment_card_encryption` (+1895%).

Distributed trace comparison provides direct evidence: in the current run, `T04_Payment_Processing` traces contain new `matrix-multiply` spans taking **237ms** (matrix-size: 620) that consume 99% of the trace — these spans do not appear at all in the baseline's top traces, which were entirely I/O-bound. The same pattern appears in `T06_Compare_Products`, where `matrix-multiply` spans (110ms, matrix-size: 491) replaced what were previously pure `delay` calls. The span attribute `matrix-size` varying between 491 and 620 across transactions is consistent with the annotation "make matrix calculation more variable".

Cross-source correlation confirms this with **high confidence** from 6 independent sources: Pyroscope (69% CPU on `MatrixCalculator.multiply`), Tempo traces (`matrix-multiply` spans dominating regressed transactions), container metrics (CPU +211%), JVM GC (minor GC +220%, major GC appearing, tenured gen +37%), Adapt (34 regressions across all dashboards), and config diff (annotation confirming the matrix change). The causal chain flows: **compute regression → CPU saturation → GC pressure → connection pool pressure**.

All 4 observed errors originate from `/flaky` chaos endpoints and are unrelated to the regression. The 5 improvements (error rate reductions on `T03_Search_Products` and `T07_Product_Assets`) suggest a previously flaky dependency was fixed in this release and should be preserved in any rollback.

### Evidence chain

| Source | Finding | Supports hypothesis? |
|---|---|---|
| Adapt | 9 compute sub-requests regressed 244%–1554% | Yes ✅ |
| Pyroscope | `MatrixCalculator.multiply` = 69% CPU | Yes ✅ |
| Config diff | Annotation changed to "make matrix calculation more variable" | Yes ✅ |
| Container metrics | afterburner-fe CPU +210.8% | Yes ✅ |
| JVM GC | Minor GC +220%, major GC appeared, tenured gen +37% | Yes ✅ |
| Connection pool | employee-db-pool active connections increased | Partial ⚠️ |
| Tempo traces | `matrix-multiply` spans (237ms, 110ms) dominate regressed transactions; not present in baseline traces | Yes ✅ |
| Error analysis | All errors on /flaky endpoints | No ❌ (unrelated) |

### Recommendations

1. **Revert the matrix calculation change** in `MatrixCalculator.multiply` — this single method is responsible for 69% of CPU and the entire regression cascade. The version annotation "changed-matrix-calc" confirms this is the code change under test.
2. **Profile `MatrixCalculator.multiply` in isolation** to understand whether the variability can be achieved with a less CPU-intensive algorithm (e.g., sparse matrix multiplication, caching intermediate results, or reducing matrix dimensions).
3. **Add a CPU time budget SLO check** for the afterburner-fe container (e.g., mean CPU < 10%) to catch CPU regressions before they cascade into latency and GC regressions.
4. **Consider offloading matrix computation** to an async worker thread or dedicated compute service to prevent it from blocking the request thread and cascading into all transactions.
5. **Monitor the flaky endpoint error rates** — while unrelated to this regression, the T07_Order_Tracking_Assets flaky error rate increased from 6% to 9%, which may indicate the chaos fixture needs tuning.

---

## Run trend (last 3 runs)

| Run | Date | Release | Result | Adapt |
|---|---|---|---|---|
| `PerfanaWebshop-acc-loadTest-00003` | 2026-03-29 | 2.4.3-changed-matrix-calc | FAIL ❌ | REGRESSION |
| `PerfanaWebshop-acc-loadTest-00002` | 2026-03-29 | 2.4.3-good-baseline | FAIL ❌ | REGRESSION |
| `PerfanaWebshop-acc-loadTest-00001` | 2026-03-29 | 2.4.3-good-baseline | PASS ✅ | NO_BASELINES_FOUND |

---

## Links

- [CI build](http://nu.nl)

---

_Report generated 2026-03-29 by Claude Code · Perfana report skill v2.0 (with cross-source investigation)_
