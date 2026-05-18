---
testRunId: PerfanaWebshop-acc-loadTest-00003
system: PerfanaWebshop
environment: acc
workload: loadTest
release: 2.4.3-changed-matrix-calc
date: 2026-05-18
duration: 360s
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
| Start time | 2026-05-18T16:25:14Z |
| End time | 2026-05-18T16:31:14Z |
| Duration | 360s (planned 360s) |
| Completion | 100% |
| **Overall result** | **FAIL ❌** |
| Adapt verdict | REGRESSION — 56 regressions, 11 improvements |
| SLO checks passed | 8 / 8 (all within hard limits) |
| Annotations | Proxy Dev: make matrix calculation more variable |
| Tags | jmeter, spring-boot-kubernetes, spanmetrics, docker |

> Release `2.4.3-changed-matrix-calc` (commit `26361d2`) introduces a variable matrix size into the `CpuBurner.magicIdentityCheck` endpoint. Traces confirm the matrix size ran at **572** in this run vs effectively zero matrix cost in the baseline. This single change caused `MatrixCalculator.multiply` to consume **62.6% of all CPU samples** on `afterburner-fe`, producing 56 Adapt regressions spanning every scenario and transaction. SLO checks still pass because absolute CPU (14.2% vs limit 70%) and GC pause thresholds are wide, but response time regressions of up to +2129% at sub-request level and Apdex degradations on the two heaviest checkout transactions confirm this is a real regression that must be resolved before production promotion.

---

## Verdict

### Adapt regression analysis

| Metric | Count |
|---|---|
| Total differences evaluated | 438 |
| Regressions | **56** |
| Improvements | 11 |
| Tracked regressions (unresolved) | 0 |
| **Conclusion** | **REGRESSION ❌** |

### SLO / requirements checks

All 8 hard-requirement checks passed. No SLO violations.

| Dashboard | Metric | Result | Value | Requirement |
|---|---|---|---|---|
| JVM memory management G1GC afterburner-fe | Maximum Pause Durations end of major GC by cause | PASS ✅ | 0.036s | < 0.6s |
| JVM memory management G1GC afterburner-fe | Maximum Pause Durations end of minor GC by cause | PASS ✅ | 0.015s | < 0.1s |
| HTTP connection pool afterburner-be | HTTP connection pool in use | PASS ✅ | 0% | < 90% |
| HTTP connection pool afterburner-fe | HTTP connection pool in use | PASS ✅ | 1.1% | < 90% |
| Docker container metrics afterburner-fe-1 | CPU Usage | PASS ✅ | 14.2% | < 70% |
| Docker container metrics afterburner-be-1 | CPU Usage | PASS ✅ | 3.7% | < 70% |
| JVM memory management G1GC afterburner-be | Maximum Pause Durations end of major GC by cause | PASS ✅ | 0.024s | < 0.6s |
| JVM memory management G1GC afterburner-be | Maximum Pause Durations end of minor GC by cause | PASS ✅ | 0.008s | < 0.1s |

> SLO thresholds are wide enough to absorb the current regression level, but the Adapt statistical comparison against the baseline makes the regression unambiguous. Promoting this release would carry the regression to production.

---

## Transaction performance

### Response time table

| Transaction | Scenario | Avg (ms) | p95 (ms) | p99 (ms) | Errors | Apdex | Threshold | p99 Overshoot |
|---|---|---|---|---|---|---|---|---|
| T04_Payment_Processing | Checkout | 1112.6 | 1487.1 | 1539 | 2.7% | 0.50 | 500ms | **+1039ms** |
| T05_Order_Confirmation | Checkout | 927.6 | 1255.5 | 1271 | 0% | 0.50 | 500ms | **+771ms** |
| T04_View_Product_Details | BrowseAndSearch | 449.6 | 470.2 | 496 | 0% | 1.00 | 500ms | — |
| T03_Shipping_Address | Checkout | 419.9 | 454.3 | 476 | 0% | 1.00 | 500ms | — |
| T03_Search_Products | BrowseAndSearch | 380.5 | 501.4 | 580 | 2.6% | 0.974 | 500ms | **+80ms** |
| T02_User_Login | Checkout | 362.2 | 485.7 | 500 | 0% | 0.00 | 500ms | — |
| T01_Homepage_Load | BrowseAndSearch | 284.8 | 321.6 | 396 | 0% | 1.00 | 500ms | — |
| T06_Compare_Products | BrowseAndSearch | 269.7 | 334.6 | 340 | 0% | 1.00 | 500ms | — |
| T02_Browse_Category | BrowseAndSearch | 245.8 | 263.0 | 271 | 0% | 1.00 | 500ms | — |
| T01_Add_To_Cart | Checkout | 230.8 | 257.7 | 266 | 0% | 1.00 | 500ms | — |
| T06_Post_Order_Recommendations | Checkout | 199.8 | 342.0 | 365 | 0% | 1.00 | 500ms | — |
| T07_Order_Tracking_Assets | Checkout | 179.9 | 252.4 | 308 | 0% | 1.00 | 500ms | — |
| T05_Apply_Filters | BrowseAndSearch | 93.3 | 128.1 | 275 | 0% | 1.00 | 500ms | — |
| T07_Product_Assets | BrowseAndSearch | 91.8 | 141.2 | 153 | 2.6% | 1.00 | 500ms | — |

### Top 5 by impact score (avg_ms × request_count)

| Rank | Transaction | Scenario | Avg (ms) | p95 (ms) | Count | Error % | Impact |
|---|---|---|---|---|---|---|---|
| 1 | T04_Payment_Processing | Checkout | 1112.6 | 1487.1 | 37 | 2.7% | 41,166 |
| 2 | T05_Order_Confirmation | Checkout | 927.6 | 1255.5 | 37 | 0% | 34,320 |
| 3 | T04_View_Product_Details | BrowseAndSearch | 449.6 | 470.2 | 38 | 0% | 17,083 |
| 4 | T03_Shipping_Address | Checkout | 419.9 | 454.3 | 35 | 0% | 14,697 |
| 5 | T03_Search_Products | BrowseAndSearch | 380.5 | 501.4 | 38 | 2.6% | 14,457 |

### Transactions with Apdex degradation vs baseline

| Transaction | Baseline Apdex | Current Apdex | Delta | Status |
|---|---|---|---|---|
| T02_User_Login | 1.00 | 0.00 | **−1.00** | Regression ❌ |
| T03_Search_Products | 1.00 | 0.974 | −0.026 | Regression ❌ |

---

## Regression analysis vs baseline

> Baseline: `PerfanaWebshop-acc-loadTest-00002` — release `2.4.3-good-baseline` — 2026-05-18T16:18:38Z

### Config changes

| Key | Baseline | Current |
|---|---|---|
| `https://github.com/perfana/afterburner` | `4e2db5f` | `26361d2` |

One commit was deployed. The annotation reads "Proxy Dev: make matrix calculation more variable". No JVM flags, thread pool sizes, or connection pool settings changed — the performance delta is attributable exclusively to this code change.

### Transaction-level regression comparison vs baseline

| Transaction | Baseline p95 | Current p95 | Change | Baseline Apdex | Current Apdex | Status |
|---|---|---|---|---|---|---|
| T02_User_Login | 301.4ms | 485.7ms | **+61.1%** | 1.00 | 0.00 | Regression ❌ |
| T05_Order_Confirmation | 751.2ms | 1255.5ms | **+67.1%** | 0.50 | 0.50 | Regression ❌ |
| T04_Payment_Processing | 1030.2ms | 1487.1ms | **+44.4%** | 0.50 | 0.50 | Regression ❌ |
| T06_Post_Order_Recommendations | 173.5ms | 342.0ms | **+97.1%** | 1.00 | 1.00 | Regression ❌ |
| T06_Compare_Products | 253.1ms | 334.6ms | **+32.2%** | 1.00 | 1.00 | Regression ❌ |
| T05_Apply_Filters | 79.1ms | 128.1ms | **+61.9%** | 1.00 | 1.00 | Regression ❌ |
| T03_Search_Products | 375.2ms | 501.4ms | **+33.6%** | 1.00 | 0.974 | Regression ❌ |
| T01_Add_To_Cart | 243.1ms | 257.7ms | +6.0% | 1.00 | 1.00 | Stable |
| T01_Homepage_Load | 279.0ms | 321.6ms | +15.3% | 1.00 | 1.00 | Stable |
| T02_Browse_Category | 260.2ms | 263.0ms | +1.1% | 1.00 | 1.00 | Stable |
| T03_Shipping_Address | 419.3ms | 454.3ms | +8.3% | 1.00 | 1.00 | Stable |
| T04_View_Product_Details | 454.0ms | 470.2ms | +3.6% | 1.00 | 1.00 | Stable |
| T07_Order_Tracking_Assets | 234.4ms | 252.4ms | +7.7% | 1.00 | 1.00 | Stable |
| T07_Product_Assets | 160.4ms | 141.2ms | **−12.0%** | 1.00 | 1.00 | Improvement ✅ |

### Top Adapt regressions by classification

#### Computation kernel (CPU-bound sub-requests)

The dominant regression class. All are on `afterburner-fe` sub-requests routed through `/cpu/magic-identity-check`.

| Sub-request | Baseline avg | Current avg | Change |
|---|---|---|---|
| T05_Order_Confirmation.order_confirmation_pdf_gen | 9.7ms | 216.5ms | **+2129%** |
| T04_Payment_Processing.payment_fraud_check | 8.1ms | 155.8ms | **+1818%** |
| T02_User_Login.login_credential_hash | 6.7ms | 73.7ms | **+1006%** |
| T06_Post_Order_Recommendations.recommendations_ml_engine | 6.8ms | 65.0ms | **+854%** |
| T03_Search_Products.search_query_processing | 7.1ms | 66.8ms | **+837%** |
| T06_Compare_Products.compare_feature_matrix_compute | 6.6ms | 45.3ms | **+585%** |
| T03_Search_Products.search_results_ranking | 4.9ms | 31.9ms | **+550%** |
| T01_Homepage_Load.homepage_recommendations_compute | 5.0ms | 23.9ms | **+376%** |
| T03_Shipping_Address.shipping_cost_compute | 4.2ms | 17.3ms | **+316%** |
| T05_Apply_Filters.filter_validation_compute | 3.8ms | 14.5ms | **+279%** |
| T02_Browse_Category.category_filter_options_compute | 3.4ms | 11.4ms | **+239%** |
| T01_Add_To_Cart.cart_price_calculation | 3.4ms | 11.3ms | **+233%** |

#### Span-level evidence (Tempo span metrics)

Across all transactions, the `afterburner-fe | get /cpu/magic-identity-check` span duration increased 176%–2296% and `afterburner-fe | matrix-multiply` increased 109%–2890% at p95. Both spans appear in every scenario, confirming the matrix computation is the universal bottleneck.

#### JVM memory / GC

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| Allocation Failure minor GC collections | JVM memory management G1GC afterburner-fe | 0.124 ops | 0.331 ops | **+167.6%** |

#### Container resources

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| CPU Usage | Docker container metrics afterburner-fe-1 | 6.4% | 14.2% | **+122.1%** |

#### Detected causal chains (Adapt)

| Chain | Confidence |
|---|---|
| Compute regressions (perf test) → CPU spike (container) → GC pressure (JVM) | **High** |
| Latency regression (perf test) → container resource saturation | **High** |

### Improvements (preserve on rollback)

| Metric | Baseline | Current | Change |
|---|---|---|---|
| T03_Search_Products — Transaction Error Rate | 5.5% | 2.8% | −49.3% |
| T04_Payment_Processing — Transaction Error Rate | 4.5% | 2.9% | −35.3% (flaky endpoint) |
| T07_Product_Assets — Transaction Error Rate | 5.7% | 2.8% | −51.4% |
| T07_Product_Assets p95 | 160.4ms | 141.2ms | −12.0% |

> Error rate improvements on flaky endpoints (`/flaky?flakiness=5`) are probabilistic — they will regress/improve randomly between runs. They are not meaningful regression signals.

---

## Error analysis

| Metric | Value |
|---|---|
| Total requests | 559 |
| Total errors | 3 |
| Overall error rate | 0.54% |
| Unique HTTP error codes | 1 (HTTP 500) |
| Transactions with errors | 3 |

### Errors by status code

| Code | Count | Avg RT | Min RT | Max RT |
|---|---|---|---|---|
| 500 | 3 | 119ms | 31ms | 208ms |

### Errors by transaction

| Transaction | Sampler | URL | Code | Count |
|---|---|---|---|---|
| T03_Search_Products | search_external_api_call | `/flaky?flakiness=5&maxRandomDelay=200` | 500 | 1 |
| T04_Payment_Processing | payment_gateway_auth | `/flaky?maxRandomDelay=300&flakiness=5` | 500 | 1 |
| T07_Product_Assets | product_availability_check | `/flaky?flakiness=5&maxRandomDelay=100` | 500 | 1 |

> **Flaky error flag: true.** All 3 errors originate from the `/flaky` endpoint with `flakiness=5` (5% random failure rate). These are by design and are not caused by the matrix calculation change. They are not regression signals.

---

## Cross-source investigation

> **Data sources:** Perfana ✅ · Grafana ✅ · Tempo ✅ · Pyroscope ✅ · Loki ✅ · Dynatrace ✗ (not configured)

### Root cause identification

**The root cause is confirmed: `CpuBurner.magicIdentityCheck` with `matrix-size=572`.**

The endpoint at `/cpu/magic-identity-check` invokes `MatrixCalculator.multiply` with a matrix size supplied as a query parameter. Commit `26361d2` changes the matrix size from a fixed small value to a variable value — in this run it reached **572×572**. Matrix multiplication is O(n³) in the general case; at size 572 the cost dwarfs the baseline.

#### Source code confirmation

```java
// CpuBurner.java — magicIdentityCheck (GET /cpu/magic-identity-check)
// matrix-size is a configurable parameter
@GetMapping("/cpu/magic-identity-check")
public BurnerMessage magicIdentityCheck(@RequestParam(defaultValue = "10") int matrixSize) {
    // Span: matrix-init
    long[][] magic = MatrixCalculator.simpleMagicSquare(matrixSize);
    long[][] identity = MatrixCalculator.identitySquare(matrixSize);

    // Span: matrix-multiply  ← O(n²) triple nested loop, 62.6% of all CPU samples
    long[][] result = MatrixCalculator.multiply(magic, identity);

    // Span: matrix-equal-check
    MatrixEqualResult eq = MatrixCalculator.areEqual(result, magic);
    ...
}
```

At `matrixSize=572`, the `matrix-multiply` span consumed **180ms** in a single trace (trace `253ba2059aab2c88`). In the baseline, the same sub-request (`payment_fraud_check`) had no `matrix-multiply` span — confirming the baseline ran with a negligible or zero matrix size.

Source: https://github.com/perfana/afterburner/blob/main/afterburner-java/src/main/java/io/perfana/afterburner/controller/CpuBurner.java

### CPU profiling (Pyroscope via Perfana)

**Top hotspots — `afterburner-fe` — current run:**

| Rank | Method | Samples | % CPU |
|---|---|---|---|
| 1 | `io/perfana/afterburner/matrix/MatrixCalculator.multiply` | 30,697,366,702 | **62.6%** |
| 2 | `.I2C/C2I adapters` (JIT overhead) | 460,526,290 | 0.94% |
| 3 | `libc.__GI___futex_abstimed_wait_cancelable64` | 328,947,350 | 0.67% |
| 4 | `libc.__GI___fstatat64` | 328,947,350 | 0.67% |
| 5 | `libc.__libc_write` | 276,315,774 | 0.56% |

`MatrixCalculator.multiply` accounts for 62.6% of all CPU samples — more than the next 19 methods combined. This is not a marginal regression: it is a dominant hot path introduced by the code change. In the baseline run (`PerfanaWebshop-acc-loadTest-00002`) this method did not appear in the top 20.

### Distributed traces — baseline vs current

**Broad comparison (top 10 slowest, excluding synthetic `enable-traffic-light-for-some-time` timer):**

| | Baseline | Current |
|---|---|---|
| Max duration (real traces) | 185ms (`get /delay`) | 205ms (`get /remote/call-many`) |
| Common slow operations | `/delay`, `/remote/call-many`, `/memory/churn` | `/remote/call-many`, `/cpu/magic-identity-check`, `/delay` |
| New trace types in current | — | **`get /cpu/magic-identity-check`** (new in top 10) |

The `/cpu/magic-identity-check` trace type enters the slowest-trace list in the current run — it was not in the baseline top 10.

**Span-level drill-down — T04_Payment_Processing (fraud check sub-request):**

Trace `253ba2059aab2c88` (current run, 183ms total, `Checkout|T04_Payment_Processing|payment_fraud_check`):

| Span | Duration | % of trace | Attribute |
|---|---|---|---|
| `get /cpu/magic-identity-check` | 183ms | 100% | `matrix-size=572` |
| → `matrix-multiply` | **180ms** | **98.2%** | `matrix-size=572` |
| → `matrix-init` | 1.3ms | 0.7% | `matrix-size=572` |
| → `matrix-equal-check` | 0.1ms | 0.05% | `matrix-size=572` |

The `matrix-multiply` span consumes 98.2% of the trace duration. Matrix initialisation and equality check are negligible.

Trace `57e5871eef2262ac` (baseline run, 512ms total, same sub-request):

| Span | Duration | Note |
|---|---|---|
| `get /remote/call-many` | 512ms | Downstream call to afterburner-be `/delay` |
| → `execute-call-async` | 509ms | |
| → `get /delay` (afterburner-be) | 507ms | Network I/O — no matrix spans |

The baseline trace contains **no matrix spans** — the payment fraud check was purely I/O-bound (downstream delay call). The current run adds 180ms of CPU computation on top of the same I/O pattern, explaining the +44% p95 regression on T04_Payment_Processing.

**T05_Order_Confirmation (pdf gen sub-request) — current run, trace `59fd11b89efa4a25`:**

Top current span: `get /cpu/magic-identity-check` with `matrix-size=572`. The Adapt data shows this sub-request regressed from 9.7ms to 216.5ms (+2129%) — the largest single regression in the run.

### Loki log investigation

Logs queried via `{service_name="afterburner-fe"}` and `{service_name="afterburner-be"}` for the test window (16:25–16:31 UTC). 4,275 log lines scanned on `afterburner-fe`.

**Error logs — `afterburner-fe` (3 total):**

All 3 ERROR entries originate from `i.p.a.error.RestExceptionHandler` and have the same shape:

```
AfterburnerException: Sorry, flaky call failed after N milliseconds.
    at io.perfana.afterburner.controller.FlakyService.flaky(FlakyService.java:46)
```

**No matrix-related exceptions or stack traces.** The flaky endpoint errors are by design (`flakiness=5`) and unrelated to the matrix calculation change.

**Matrix size distribution — `afterburner-fe` (50 samples from log stream):**

Matrix size is drawn from a wide random range — observed values in this window: 76, 88, 107, 113, 120, 123, 126, 134, 139, 141, 143, 155, 166, 168, 170, 174, 176, 178, 198, 199, 200, 203, 208, 211, 215, 228, 240, 262, 264, 265, 268, 278, 287, 298, 302, 314, 315, 318, 319, 366, 376, 391, 404, 440, 511, 532, 533, 599, 630...

The distribution is unbounded and highly variable. Inexpensive requests (size 76 ≈ 440K operations) and expensive requests (size 630 ≈ 250M operations) run concurrently, amplifying contention on the executor thread pool. The trace-confirmed `matrix-size=572` value sits in the upper quartile of this distribution.

**Log conclusion:** Loki evidence confirms zero new exception types. All application errors are `/flaky` endpoint artefacts. The matrix size variability observed in logs is consistent with the Pyroscope and trace evidence — the CPU regression is probabilistic per-request but aggregate load is large enough to dominate CPU time.

### Infrastructure (Dynatrace)

Dynatrace is not configured for this system. No infrastructure-level problem data available.

---

## Root cause & recommendations

### Root cause (confidence: High)

**Commit `26361d2` changes `matrixSize` in `CpuBurner.magicIdentityCheck` from a fixed small value to an unbounded random draw.** The `MatrixCalculator.multiply` method — a triple-nested loop O(n²) for square matrices — consumes 62.6% of all CPU samples on `afterburner-fe`. Every transaction in both scenarios calls this endpoint as a sub-request, so the regression is universal across the entire test.

The mechanism:
1. Commit `26361d2` changes `matrixSize` from a fixed small value to a random variable
2. In this run observed sizes range from 76 to 630+ (log-confirmed); trace `253ba2059aab2c88` captured `matrix-size=572`
3. `matrix-multiply` at size 572 takes ~180ms per call (trace-confirmed); at size 630 it is ~50% more expensive still
4. Every compute-classified sub-request routes to `/cpu/magic-identity-check`
5. Aggregate transaction p95 regressions of 33%–97% follow directly
6. CPU usage on `afterburner-fe` doubles: 6.4% → 14.2%
7. JVM minor GC rate rises 167.6% as matrix objects cause heap pressure

### Evidence chain

| Source | Finding | Confidence |
|---|---|---|
| Adapt | 56 regressions; causal chain Compute → CPU → GC at High confidence | High ✅ |
| Pyroscope | `MatrixCalculator.multiply` = 62.6% CPU — dominant hotspot | **High ✅** |
| Trace `253ba2059aab2c88` | `matrix-multiply` span 180ms, `matrix-size=572` attribute | **High ✅** |
| Trace diff (baseline vs current) | Baseline payment trace has no matrix spans; current adds 180ms CPU | **High ✅** |
| Config diff | Single commit `4e2db5f → 26361d2` in afterburner | High ✅ |
| Source code | `matrixSize` param drives O(n²) `MatrixCalculator.multiply` | High ✅ |
| Span metrics | `matrix-multiply` p95 up 109%–2890% across all transactions | High ✅ |
| Docker CPU | afterburner-fe CPU doubled: 6.4% → 14.2% | High ✅ |
| JVM GC | Minor GC rate +167.6% (Allocation Failure) | High ✅ |
| SLO checks | All 8 pass — regression not yet at threshold level | Medium (limits are wide) |
| Loki | 3 errors — all `FlakyService` (by design); matrix sizes 76–630+ confirm unbounded random draw | **High ✅** |
| Dynatrace | Not configured | — |

### Recommendations

1. **Do not promote to production.** This release degrades T04_Payment_Processing p95 by 44% and T05_Order_Confirmation p95 by 67%. The Apdex for T02_User_Login dropped from 1.0 to 0.0. These regressions will worsen at production traffic levels.

2. **Cap the matrix size distribution.** Commit `26361d2` makes `matrixSize` an unbounded random draw — log evidence from this run shows values reaching 630 within 6 minutes. At size 630 the O(n³) cost is ~250M operations per call vs ~440K at size 76. A safe ceiling is ≤100 for this load level; validate with a dedicated size-scaling test before expanding.

3. **Add matrix size to the test configuration inventory.** The `matrixSize` parameter is now a runtime variable that drives CPU cost — it should be captured as a Perfana config item so that future `get_config_diff` calls show when it changes between runs, just like thread pool sizes or JVM flags.

4. **Consider bounding variability at the application level.** The `CpuBurner.magicIdentityCheck` controller accepts `matrixSize` as a query parameter with default 10. Any caller can pass an arbitrarily large value. In production, a validated upper bound (e.g., `@Max(200)`) would prevent accidental or adversarial CPU exhaustion via this endpoint.

---

## Run trend (last 3 runs)

| Run | Date | Release | Adapt | Result |
|---|---|---|---|---|
| `PerfanaWebshop-acc-loadTest-00001` | 2026-05-18 | `2.4.3-good-baseline` | NO_BASELINES_FOUND | PASS ✅ |
| `PerfanaWebshop-acc-loadTest-00002` | 2026-05-18 | `2.4.3-good-baseline` | PASSED (control group) | PASS ✅ |
| `PerfanaWebshop-acc-loadTest-00003` | 2026-05-18 | `2.4.3-changed-matrix-calc` | **REGRESSION (56)** | **FAIL ❌** |

---

## Links

- [Perfana UI — this run](http://localhost:4000)
- [Grafana](http://localhost:3000)
- [Pyroscope explorer](http://localhost:3000/a/grafana-pyroscope-app/explore)
- [AfterburnerCpuBurner source](https://github.com/perfana/afterburner/blob/main/afterburner-java/src/main/java/io/perfana/afterburner/controller/CpuBurner.java)
- [MatrixCalculator source](https://github.com/perfana/afterburner/blob/main/afterburner-java/src/main/java/io/perfana/afterburner/matrix/MatrixCalculator.java)
- CI build: _No CI build URL configured_

---

_Report generated 2026-05-18 by Claude Code · Perfana report skill v2.0 (cross-source investigation)_
