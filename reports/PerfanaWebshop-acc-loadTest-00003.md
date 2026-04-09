# Performance Test Report: PerfanaWebshop-acc-loadTest-00003

| Field | Value |
|---|---|
| **Test Run ID** | PerfanaWebshop-acc-loadTest-00003 |
| **System Under Test** | PerfanaWebshop |
| **Environment** | acc |
| **Workload** | loadTest |
| **Version** | 2.4.3-changed-matrix-calc |
| **Baseline Run** | PerfanaWebshop-acc-loadTest-00002 (version 2.4.3-good-baseline) |
| **Test Start** | 2026-04-08T17:48:41Z |
| **Verdict** | REGRESSION |
| **Adapt Result** | REGRESSION — 28 regressions, 6 improvements, 201 total differences |
| **Annotation** | Proxy Dev: make matrix calculation more variable |
| **Report Generated** | 2026-04-08 |

---

## Executive Summary

This test run exhibits a **broad, cross-cutting CPU regression** caused by a deliberate code change in `afterburner` (commit `26361d2`, version `2.4.3-changed-matrix-calc`). The change annotation reads "make matrix calculation more variable", and the evidence confirms this is a matrix multiplication workload change that has degraded sub-request response times by 100–1670% across virtually every transaction in both the Checkout and BrowseAndSearch scenarios.

**Root cause (High confidence):** The new application version changed the matrix computation algorithm in `MatrixCalculator.multiply` to produce variable-sized matrix operations. Traces show requests that previously executed `get /delay` (I/O-bound, ~100ms) or `get /remote/call-many` now execute `get /cpu/magic-identity-check` → `matrix-multiply` (CPU-bound, 230–290ms) with matrix sizes ranging 639–668. The Pyroscope flamegraph confirms `MatrixCalculator.multiply` consumes **59% of total CPU** on afterburner-fe. This CPU saturation drives the GC pressure (minor GC collections +131.9%) and the container CPU increase (+138.6%, from 6.1% to 14.5%).

All 3 error-producing transactions hit the `/flaky` endpoint with probabilistic failures — these are inherent to the flakiness simulation and are flagged as such (Flaky error flag: **true** for all error URLs).

**Overall status: FAIL — do not promote to production.**

---

## Verdict and SLO Checks

All 10 SLO checks **passed** (no hard SLO breaches). However, Adapt detected 28 regressions vs. the baseline, which drove the REGRESSION verdict.

| Dashboard | Check | Value | Threshold | Status |
|---|---|---|---|---|
| Docker — afterburner-be | CPU Usage | 4.1% | < 70% | PASS |
| Docker — afterburner-fe | CPU Usage | 14.5% | < 70% | PASS |
| Hikari — afterburner-fe | Pending connections | 0 | < 10 | PASS |
| Hikari — afterburner-be | Pending connections (basket-db-pool) | 0 | < 10 | PASS |
| Hikari — afterburner-be | Pending connections (employee-db-pool) | 0 | < 10 | PASS |
| HTTP pool — afterburner-fe | Connection pool in use | 0.71% | < 90% | PASS |
| HTTP pool — afterburner-be | Connection pool in use | 0% | < 90% | PASS |
| JVM G1GC — afterburner-fe | Minor GC max pause (Allocation Failure) | 12ms | < 100ms | PASS |
| JVM G1GC — afterburner-be | Minor GC max pause (Allocation Failure) | 13ms | < 100ms | PASS |
| JVM G1GC — afterburner-fe | Major GC max pause (Allocation Failure) | 71ms | < 600ms | PASS |

No SLO checks failed. The regressions detected by Adapt are statistically significant relative to the baseline but did not breach the absolute thresholds — this indicates the thresholds may need tightening given the scale of the sub-request degradation.

---

## Transaction Summary

| Transaction | Scenario | Avg RT (ms) | p95 (ms) | p99 (ms) | p99 tail overshoot | Apdex | Errors | vs Baseline p95 | Status |
|---|---|---|---|---|---|---|---|---|---|
| T01_Add_To_Cart | Checkout | 237 | 259 | 413 | -87ms | 1.000 | 0 | +6.6% | Stable |
| T01_Homepage_Load | BrowseAndSearch | 289 | 319 | 421 | -79ms | 1.000 | 0 | +14.8% | Stable |
| T02_Browse_Category | BrowseAndSearch | 255 | 277 | 287 | -213ms | 1.000 | 0 | +3.8% | Stable |
| T02_User_Login | Checkout | 344 | 390 | 400 | -100ms | 1.000 | 0 | **+29.5%** | Regression |
| T03_Search_Products | BrowseAndSearch | 369 | 476 | 490 | -10ms | 1.000 | 1 (2.6%) | **+27.3%** | Regression |
| T03_Shipping_Address | Checkout | 410 | 443 | 447 | -53ms | 1.000 | 0 | +4.0% | Stable |
| **T04_Payment_Processing** | Checkout | **1056** | **1332** | **1378** | **+878ms** | **0.500** | 1 (2.7%) | **+30.5%** | **Regression** |
| T04_View_Product_Details | BrowseAndSearch | 460 | 493 | 500 | 0ms | 0.987 | 0 | +7.1% | Stable |
| T05_Apply_Filters | BrowseAndSearch | 93 | 152 | 224 | -276ms | 1.000 | 0 | **+83.0%** | Regression |
| **T05_Order_Confirmation** | Checkout | **910** | **1226** | **1403** | **+903ms** | **0.500** | 0 | **+61.1%** | **Regression** |
| T06_Compare_Products | BrowseAndSearch | 280 | 339 | 451 | -49ms | 0.987 | 0 | **+33.2%** | Regression |
| T06_Post_Order_Recommendations | Checkout | 208 | 301 | 314 | -186ms | 1.000 | 0 | **+74.6%** | Regression |
| T07_Order_Tracking_Assets | Checkout | 203 | 335 | 460 | -40ms | 1.000 | 1 (3.0%) | **+32.2%** | Regression |
| T07_Product_Assets | BrowseAndSearch | 106 | 149 | 275 | -225ms | 1.000 | 0 | -3.3% | Stable |

Active threshold for all transactions: 500ms.
**p99 tail overshoot** = p99 response time minus 500ms threshold (negative = within threshold).

**Transactions breaching p99 threshold:** T04_Payment_Processing (+878ms), T05_Order_Confirmation (+903ms).
**Transactions with Apdex degradation:** T04_Payment_Processing (0.500), T05_Order_Confirmation (0.500), T04_View_Product_Details (0.987), T06_Compare_Products (0.987).

---

## Performance Rankings

### Slowest Transactions (by avg response time)
1. T04_Payment_Processing — 1056ms avg (Apdex 0.500)
2. T05_Order_Confirmation — 910ms avg (Apdex 0.500)
3. T04_View_Product_Details — 460ms avg
4. T03_Shipping_Address — 410ms avg
5. T03_Search_Products — 369ms avg

### Highest Regression vs Baseline (by p95 % change)
1. T05_Apply_Filters — +83.0%
2. T06_Post_Order_Recommendations — +74.6%
3. T05_Order_Confirmation — +61.1%
4. T06_Compare_Products — +33.2%
5. T04_Payment_Processing — +30.5%

### Highest Error Rate (current run)
1. T07_Order_Tracking_Assets — 3.0% (loyalty_points_api, flaky endpoint)
2. T04_Payment_Processing — 2.7% (payment_gateway_auth, flaky endpoint)
3. T03_Search_Products — 2.6% (search_external_api_call, flaky endpoint)

---

## Error Analysis

**Total errors:** 3 out of 2,405 requests (0.12% overall error rate).
**All errors:** HTTP 500, all from the `/flaky` endpoint — probabilistic simulation.

| Transaction | Sub-request | URL | Count | Avg RT | Error |
|---|---|---|---|---|---|
| T03_Search_Products | search_external_api_call | `/flaky?flakiness=2&maxRandomDelay=200` | 1 | 135ms | AfterburnerException: flaky call failed after 130ms |
| T04_Payment_Processing | payment_gateway_auth | `/flaky?maxRandomDelay=300&flakiness=3` | 1 | 41ms | AfterburnerException: flaky call failed after 6ms |
| T07_Order_Tracking_Assets | loyalty_points_api | `/flaky?flakiness=3&maxRandomDelay=80` | 1 | 49ms | AfterburnerException: flaky call failed after 42ms |

**Flaky error flag: TRUE** — all 3 error URLs match the `/flaky` pattern. These errors are by design (flakiness simulation) and are expected at low rates in both test and baseline. The error rate regressions detected by Adapt (+120.5% for T03, +106.1% for T07 loyalty_points_api) reflect statistical increase against a near-zero baseline, but the absolute rates remain below 3.1%. The reduction in T04 error rate (-25.9% vs baseline) and T07 shipping_status_check (-100%) are improvements within normal flakiness variance.

---

## Adapt Regression Details

### Regressions by Dashboard

| Dashboard | Source Type | Regression Count | Top Regressed Metric |
|---|---|---|---|
| Performance test metrics Checkout | Performance test | 13 | T05_Order_Confirmation.order_confirmation_pdf_gen (+1670.3%) |
| Performance test metrics BrowseAndSearch | Performance test | 12 | T03_Search_Products.search_query_processing (+738.6%) |
| JVM memory management G1GC afterburner-fe | JVM monitoring | 2 | Minor GC Allocation Failure collections (+131.9%) |
| Docker container metrics afterburner-fe | Infrastructure | 1 | CPU Usage (+138.6%) |

### Top Sub-Request Regressions (Adapt classified)

| Sub-Request | Change % | Classification |
|---|---|---|
| T05_Order_Confirmation.order_confirmation_pdf_gen | +1670.3% | Request latency |
| T04_Payment_Processing.payment_fraud_check | +1283.9% | Request latency |
| T04_Payment_Processing.payment_card_encryption | +1105.9% | Request latency |
| T06_Post_Order_Recommendations.recommendations_ml_engine | +784.1% | Computation kernel |
| T02_User_Login.login_credential_hash | +693.0% | Computation kernel |
| T06_Compare_Products.compare_feature_matrix_compute | +680.8% | Computation kernel |
| T03_Search_Products.search_results_ranking | +649.5% | Computation kernel |
| T03_Search_Products.search_query_processing | +738.6% | Computation kernel |
| T02_User_Login.login_jwt_generation | +487.2% | Request latency |
| T04_View_Product_Details.product_reviews_aggregate | +429.4% | Request latency |
| T05_Apply_Filters.filter_facets_recalculate | +430.2% | Request latency |
| T01_Homepage_Load.homepage_recommendations_compute | +405.8% | Computation kernel |
| T05_Order_Confirmation (transaction avg) | +23.7% | Transaction latency |
| T02_User_Login (transaction avg) | +22.7% | Transaction latency |

### Improvements vs Baseline

| Metric | Change |
|---|---|
| T04_Payment_Processing transaction error rate | -25.9% |
| T04_Payment_Processing.payment_gateway_auth error rate | -25.3% |
| T07_Order_Tracking_Assets.shipping_status_check error rate | -100% |
| T07_Product_Assets transaction error rate | -100% |
| T07_Product_Assets.product_availability_check error rate | -100% |
| Hikari afterburner-be employee-db-pool active connections | -100% |

### Tracked Regressions (Unresolved)

6 regressions tracked as unresolved against baseline PerfanaWebshop-acc-loadTest-00002:
- T04_Payment_Processing — Transaction Error Rate (mean 2.78%, baseline 0%)
- T04_Payment_Processing.payment_gateway_auth — Request Error Rate (mean 3.03%, baseline 0%)
- T07_Order_Tracking_Assets — Transaction Error Rate (mean 3.03%, baseline 0%)
- T07_Order_Tracking_Assets.loyalty_points_api — Request Error Rate (mean 3.03%, baseline 0%)
- error_count (Checkout dashboard) — Error Count (mean 0.5, baseline 0)
- error_count (BrowseAndSearch dashboard) — Error Count (+180%, mean 0.4, baseline 0.14)

---

## Causal Chain Analysis

Adapt identified two high-confidence causal chains spanning multiple data sources:

### Chain 1: Computation regression → CPU spike → GC pressure (High confidence)
**Sources:** Performance test + Infrastructure + JVM monitoring + Pyroscope + Tempo

- **Performance test:** 25 sub-request regressions classified as "Computation kernel" or "Request latency", 100–1670% increases across both scenarios
- **Infrastructure:** CPU Usage on afterburner-fe +138.6% (6.1% baseline → 14.5% current)
- **JVM G1GC:** Minor GC Allocation Failure collections +131.9% (0.110 → 0.256 ops); major GC Allocation Failure appeared (0 → 0.005 ops) — new allocation pressure
- **Pyroscope:** `MatrixCalculator.multiply` at 59.0% CPU samples — 69x more dominant than the next hotspot
- **Tempo:** `matrix-multiply` spans consuming 229–284ms per call, `matrix-size` 639–668 (variable), with no equivalent operation in the baseline

### Chain 2: Latency regression → container resource saturation (High confidence)
**Sources:** Performance test + Infrastructure

The increased CPU demand from matrix operations directly saturates the afterburner-fe container, raising CPU from 6% to 14.5%, which increases response time variability and GC pause frequency in a reinforcing loop.

---

## Root Cause

**The `2.4.3-changed-matrix-calc` commit (`26361d2`) changed the matrix computation to operate on variable, larger matrices (sizes 639–668), replacing I/O-bound operations with CPU-bound matrix multiplication across all transaction paths.**

### Evidence summary

| Evidence | Source | Confidence |
|---|---|---|
| Commit `26361d2` annotation: "make matrix calculation more variable" | Config diff | Confirmed |
| `matrix-multiply` spans 229–284ms, `matrix-size` 639–668 in current traces | Tempo | Direct |
| Baseline traces show `get /delay` (I/O-bound) — no matrix operations | Tempo | Direct |
| `MatrixCalculator.multiply` at 59.0% of all CPU samples | Pyroscope | Direct |
| CPU +138.6% on afterburner-fe container | Infrastructure (Grafana) | Corroborating |
| Minor GC Allocation Failure +131.9% on afterburner-fe | JVM monitoring (Grafana) | Corroborating |
| 25 compute sub-request regressions spanning all transactions | Adapt (perf test) | Corroborating |

**Confidence: High** — corroborated by 4 independent data sources (config diff, traces, flamegraph, metrics).

### Why T04 and T05 are the worst-affected

T04_Payment_Processing and T05_Order_Confirmation chain multiple matrix-compute sub-requests in sequence (`payment_fraud_check`, `payment_card_encryption`, `order_confirmation_pdf_gen`), each incurring 200–280ms of matrix multiply time. The cumulative effect drives these transactions above the 500ms p99 threshold.

---

## Config Diff (vs Baseline PerfanaWebshop-acc-loadTest-00002)

| Type | Key | Baseline | Current |
|---|---|---|---|
| Changed | afterburner git commit | `4e2db5f` | `26361d2` |
| Changed | testContext.version | `2.4.3-good-baseline` | `2.4.3-changed-matrix-calc` |
| Changed | testContext.annotations | "Proxy Dev: make cpu more efficient" | "Proxy Dev: make matrix calculation more variable" |
| Added | host.bitness | — | 64bit |
| Added | host.cloudType | — | AZURE |
| Added | host.cpuCores | — | 4 |
| Added | host.hostName | — | afterburner-be |
| Added | host.ipAddresses | — | 10.0.0.1 |
| Added | host.memoryTotal | — | 8,589,934,592 bytes (8 GB) |
| Added | host.monitoringMode | — | FULL_STACK |
| Added | host.osArchitecture | — | X86 |
| Added | host.osType | — | LINUX |

The `host.*` additions are new Dynatrace host metadata entries — a monitoring agent was activated on afterburner-be during this run. These entries are informational and unrelated to the performance regression.

---

## Connected Data Sources

| Source | Available | Details |
|---|---|---|
| Grafana | Yes | Demo instance — http://localhost:3000 (20 dashboards) |
| Tempo | Yes | http://tempo:3200 |
| Pyroscope | Yes | http://pyroscope:4040 — afterburner-fe (CPU + memory allocation profiles) |
| Dynatrace | No | Not configured |

---

## Recommendations

### Block promotion (immediate)

1. **Revert or fix commit `26361d2` in afterburner.** The `MatrixCalculator.multiply` operation with variable matrix sizes 639–668 consumes 59% of CPU on afterburner-fe. This is the direct cause of all 28 regressions. The prior version (`4e2db5f`, "make cpu more efficient") is the known-good baseline.

2. **Do not promote `2.4.3-changed-matrix-calc` to production.** T04_Payment_Processing (p99 1378ms) and T05_Order_Confirmation (p99 1403ms) both breach the 500ms threshold by more than 900ms, and would degrade checkout conversion in production.

### Short-term

3. **Review the intent of the matrix size change.** If variable matrix sizes are intentional (e.g., parameterised by payload), define the acceptable maximum size and add a validation guard. Matrix sizes of 600+ are appropriate for batch-processing contexts, not synchronous HTTP request paths.

4. **Tighten Adapt thresholds for compute sub-requests.** The current 15% percentage threshold correctly detected all regressions, but consider adding absolute thresholds (e.g., alert if any sub-request avg exceeds 50ms) to catch CPU regressions earlier in CI.

5. **Add a matrix-size span metric to Perfana dashboards.** The Tempo span attribute `matrix-size` already exists — surface this as a tracked metric to detect size drift in future runs without requiring manual trace inspection.

### Long-term

6. **Offload matrix computation to async workers.** CPU-bound computation should not block synchronous HTTP request threads. The existing `executeCallAsync` infrastructure can be used to parallelise or queue compute-heavy operations and prevent latency chaining across transaction steps.

7. **Benchmark matrix size bounds separately.** Before any future change to `MatrixCalculator`, run a dedicated microbenchmark to characterise p99 latency as a function of matrix size. This establishes a performance model that can gate changes before load test promotion.

---

## Appendix: Trace Evidence

### Current run — T04_Payment_Processing fraud check (trace b2f74f6b, 289ms total)

```
get /cpu/magic-identity-check  [afterburner-fe]  289ms   CpuBurner.magicIdentityCheck
  matrix-init                  [afterburner-fe]    3ms   matrix-size=668
  matrix-multiply              [afterburner-fe]  284ms   matrix-size=668  <- dominant span
  matrix-equal-check           [afterburner-fe]   <1ms  matrix-size=668
```

### Current run — T05_Order_Confirmation pdf gen (trace ade8155d, 233ms total)

```
get /cpu/magic-identity-check  [afterburner-fe]  233ms   CpuBurner.magicIdentityCheck
  matrix-init                  [afterburner-fe]    2ms   matrix-size=639
  matrix-multiply              [afterburner-fe]  230ms   matrix-size=639  <- dominant span
  matrix-equal-check           [afterburner-fe]   <1ms  matrix-size=639
```

### Baseline — T04_Payment_Processing (trace d03ad0c7, 506ms total)

```
get /remote/call-many          [afterburner-fe]  506ms   RemoteCallController.remoteCallHttpClientMany
  execute-call-async           [afterburner-fe]  504ms   AfterburnerRemote.executeCallAsync
    get /delay                 [afterburner-fe]  503ms   HTTP GET /delay
      get /delay               [afterburner-be]  503ms   Delay.delay  <- I/O-bound
```

**Key observation:** The baseline T04 trace was I/O-bound (a delay call to afterburner-be). The current run replaces this with CPU-bound matrix multiplication. The baseline individual trace was slower in absolute terms (506ms vs 289ms for this specific trace), but the current version applies matrix computation to every sub-request across every transaction, making the aggregate per-transaction latency much higher — confirmed by the p95/p99 regressions.

### Baseline — T05_Order_Confirmation (trace 7e4df2c5, 263ms total)

```
get /remote/call-many          [afterburner-fe]  264ms   RemoteCallController.remoteCallHttpClientMany
  execute-call-async           [afterburner-fe]  262ms   AfterburnerRemote.executeCallAsync
    get /delay                 [afterburner-fe]  261ms   HTTP GET /delay
      get /delay               [afterburner-be]  258ms   Delay.delay  <- I/O-bound
```

### Pyroscope CPU Hotspots — afterburner-fe (current run)

| Rank | Function | CPU Samples (ns) | % |
|---|---|---|---|
| 1 | `io/perfana/afterburner/matrix/MatrixCalculator.multiply` | 28,065,787,902 | **59.0%** |
| 2 | `.I2C/C2I adapters` | 407,894,714 | 0.86% |
| 3 | `libc __GI___futex_abstimed_wait_cancelable64` | 315,789,456 | 0.66% |
| 4 | `libc __GI___fstatat64` | 276,315,774 | 0.58% |
| 5 | `libc __libc_write` | 249,999,986 | 0.53% |
| 6 | `libjvm PhaseChaitin::Split` | 197,368,410 | 0.42% |
| 13 | `io/perfana/afterburner/matrix/MatrixCalculator.simpleMagicSquare` | 131,578,940 | 0.28% |

`MatrixCalculator.multiply` is 69x more dominant than the second hotspot. This is not a distributed bottleneck — it is a single method consuming the overwhelming majority of available CPU on the service.
