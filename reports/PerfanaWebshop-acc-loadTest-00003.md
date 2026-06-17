# Performance Test Report — PerfanaWebshop-acc-loadTest-00003

## Verdict

**REGRESSION** — Adapt failed (`adaptTestRunOK: false`). SLO requirement checks passed (`meetsRequirement: true`), but automated regression analysis flagged 31 regressions against the control-group baseline.

| Field | Value |
|---|---|
| Test run | `PerfanaWebshop-acc-loadTest-00003` |
| System under test | PerfanaWebshop |
| Environment / Workload | acc / loadTest |
| Release | `2.4.3-changed-matrix-calc` |
| Annotation | "Proxy Dev: make matrix calculation more variable" |
| Start / End | 2026-06-17 15:32:30Z → 15:38:31Z (360s) |
| Baseline | `PerfanaWebshop-acc-loadTest-00002` (control group, release `2.4.3-good-baseline`) |
| Adapt | REGRESSION — 31 regressions, 0 improvements, 262 differences |
| Requirement checks | PASS (8/8 SLOs met) |

## Root Cause (High confidence)

**A code change in the afterburner application randomised the matrix dimension used by the CPU-burn workload, inflating per-request CPU cost by up to ~64x and making it highly variable.**

The config diff shows exactly one change between baseline and this run — the afterburner git SHA:

| Item | Baseline | Current |
|---|---|---|
| `https://github.com/perfana/afterburner` | `4e2db5f` | `26361d2` |

The changed method is `CpuBurner.magicIdentityCheck` in
`afterburner-java/src/main/java/io/perfana/afterburner/controller/CpuBurner.java`:

```java
// BASELINE (4e2db5f) — fixed work
// no variation: is no fun!
int funSize = matrixSize;

// CURRENT (26361d2) — randomised work
// some variation: is more fun!
int funSize = (int) (matrixSize * (1.0 + (random.nextDouble() * 3)));
```

`funSize` now ranges from 1x to **4x** the requested `matrixSize` per call. Matrix
multiplication is **O(n³)** (triple-nested loop in `MatrixCalculator.multiply`, lines 55-67):

```java
for (int m = 0; m < matrixAm; m++) {
    for (int p = 0; p < matrixBp; p++) {
        long sum = 0;
        for (int n = 0; n < matrixAn; n++) {
            sum = sum + (matrixA[m][n] * matrixB[n][p]);
            ...
        }
    }
}
```

A 4x larger dimension therefore costs up to 4³ = **64x** the CPU, and the random multiplier
makes runtime swing call-to-call — which is precisely why tail latencies (p99) exploded far
more than averages.

Source: https://github.com/perfana/afterburner/blob/main/afterburner-java/src/main/java/io/perfana/afterburner/controller/CpuBurner.java

### Evidence chain

| Source | Evidence | Result |
|---|---|---|
| Config diff | Only afterburner SHA changed `4e2db5f` → `26361d2` | Yes |
| Source code | `funSize` randomised 1x–4x; O(n³) multiply | Yes (confirmed in both SHAs) |
| Pyroscope (Perfana) | `MatrixCalculator.multiply` = **68.4%** of CPU samples | Yes |
| Pyroscope (Grafana, independent) | `multiply` lines 58-62 ≈ 68% of 50.3s CPU, reached via `CpuBurner.magicIdentityCheck:63` | Yes (corroborates) |
| Adapt — Infrastructure | afterburner-fe container CPU **+142.6%** (4.6% → 11.2%) | Yes |
| Adapt — JVM | minor-GC Allocation Failure rate **+111.4%** (larger transient `long[][]` arrays) | Yes |
| Adapt causal chain | "Compute regressions → CPU spike → GC pressure" flagged **High confidence** | Yes |

Two independent profilers, the infrastructure metric, the JVM GC metric, the config diff, and
the source code all agree. Confidence: **High**.

## Regression Summary (Adapt)

31 regressions across 4 dashboards. The dominant class is **Computation kernel** — the
`*_compute`/`*_processing` sub-requests that drive the matrix burn.

### Top regressions by magnitude

| Metric | Class | Baseline | Current | Change |
|---|---|---|---|---|
| T05_Order_Confirmation.order_confirmation_pdf_gen | Request latency | 7.9 ms | 202.7 ms | **+2474%** |
| T04_Payment_Processing.payment_fraud_check | Request latency | 6.6 ms | 165.1 ms | **+2414%** |
| T03_Search_Products.search_query_processing | Computation kernel | 4.9 ms | 73.9 ms | **+1411%** |
| T04_Payment_Processing.payment_card_encryption | Request latency | 6.9 ms | 102.7 ms | **+1380%** |
| T03_Search_Products.search_results_ranking | Computation kernel | 3.6 ms | 50.9 ms | **+1307%** |
| T06_Post_Order_Recommendations.recommendations_ml_engine | Computation kernel | 4.8 ms | 67.2 ms | **+1305%** |
| T02_User_Login.login_credential_hash | Computation kernel | 4.4 ms | 58.3 ms | **+1222%** |
| T06_Compare_Products.compare_feature_matrix_compute | Computation kernel | 5.7 ms | 66.9 ms | **+1076%** |
| T05_Apply_Filters.filter_facets_recalculate | Request latency | 3.0 ms | 34.7 ms | **+1061%** |
| T02_User_Login.login_jwt_generation | Request latency | 3.0 ms | 22.9 ms | **+667%** |

### By dashboard / source

| Dashboard | Source type | Regressions |
|---|---|---|
| Performance test metrics Checkout | Performance test | 15 |
| Performance test metrics BrowseAndSearch | Performance test | 14 |
| JVM memory management G1GC afterburner-fe | JVM monitoring | 1 (GC Allocation Failure +111.4%) |
| Docker container metrics afterburner-fe-1 | Infrastructure | 1 (CPU +142.6%) |

### Detected causal chains (Adapt, High confidence)

- Compute regressions (perf test) → CPU spike (container) → GC pressure (JVM)
- Latency regression (perf test) → container resource saturation

## Transaction-level comparison (vs baseline 00002)

Tail latency (p99) regressed far more than averages — the signature of variable per-request work.

| Transaction | p95 base→cur | p99 base→cur (Δ) | Apdex Δ | Status |
|---|---|---|---|---|
| T05_Apply_Filters | 62→207 ms | 67→596 ms (**+790%**) | -0.011 | regression |
| T04_Payment_Processing | 1024→1443 ms | 1098→1714 ms (+56%) | 0 | regression |
| T05_Order_Confirmation | 734→1407 ms | 810→1755 ms (+117%) | 0 | regression |
| T01_Add_To_Cart | 226→414 ms | 226→774 ms (+243%) | -0.021 | regression |
| T02_User_Login | 282→489 ms | 309→661 ms (+114%) | -0.023 | regression |
| T01_Homepage_Load | 275→405 ms | 276→789 ms (+186%) | -0.019 | regression |
| T06_Compare_Products | 236→420 ms | 239→461 ms (+93%) | 0 | regression |
| T06_Post_Order_Recommendations | 153→332 ms | 158→336 ms (+113%) | 0 | regression |
| T03_Search_Products | 353→613 ms | 357→683 ms (+91%) | -0.082 | regression |
| T02_Browse_Category | 251→262 ms | 263→270 ms | 0 | stable |
| T03_Shipping_Address | 394→451 ms | 398→520 ms | -0.012 | stable |
| T04_View_Product_Details | 476→471 ms | 484→472 ms | 0 | stable |
| T07_Order_Tracking_Assets | 267→278 ms | 282→299 ms | 0 | stable |
| T07_Product_Assets | 142→169 ms | 149→281 ms | 0 | stable |

The two highest-impact transactions, **T04_Payment_Processing** (avg 1155 ms, impact 36963) and
**T05_Order_Confirmation** (avg 918 ms, impact 29370), both sit at Apdex 0.5 — they were already
the slowest endpoints and the regression pushed their tails further past the 500 ms threshold.

## Errors

Error rate is **not** a regression. Overall 7 errors / 563 requests = **1.24%**, within SLO and
roughly flat versus baseline.

| Transaction | Sampler | URL | Count | Code |
|---|---|---|---|---|
| T03_Search_Products | search_external_api_call | /flaky?flakiness=5&maxRandomDelay=200 | 3 | 500 |
| T04_Payment_Processing | payment_gateway_auth | /flaky?flakiness=5&maxRandomDelay=300 | 2 | 500 |
| T07_Product_Assets | product_availability_check | /flaky?flakiness=5&maxRandomDelay=100 | 2 | 500 |

All 7 errors are 500s from the synthetic `/flaky` endpoint (`flakiness=5` = ~5% injected failure
rate by design). Response bodies are `AfterburnerException: Sorry, flaky call failed after N
milliseconds` — intentional, not caused by this release. **Flaky-only error flag: true.**

## SLO Checks (all passed)

| Dashboard | Panel | Requirement | Value | Result |
|---|---|---|---|---|
| JVM G1GC afterburner-fe | Max pause major GC | < 0.6 s | 0.103 s | PASS |
| JVM G1GC afterburner-fe | Max pause minor GC | < 0.1 s | 0.015 s | PASS |
| JVM G1GC afterburner-be | Max pause major GC | < 0.6 s | 0.059 s | PASS |
| JVM G1GC afterburner-be | Max pause minor GC | < 0.1 s | 0.017 s | PASS |
| Docker afterburner-be-1 | CPU | < 70% | 3.37% | PASS |
| Docker afterburner-fe-1 | CPU | < 70% | 11.24% | PASS |
| HTTP conn pool afterburner-be | In use | < 0.9 | 0.0 | PASS |
| HTTP conn pool afterburner-fe | In use | < 0.9 | 0.002 | PASS |

The SLO thresholds are absolute and lenient (CPU < 70%); the workload only reached ~11% CPU, so
the regression slipped past the fixed checks. **Adapt's baseline-relative analysis is what caught
it** — this is the intended demonstration: relative regression detection finds problems that
absolute thresholds miss.

## Investigation notes

- **Pyroscope (Perfana + Grafana):** both confirm `MatrixCalculator.multiply` as the single
  dominant hotspot (~68%). Call path: `CpuBurner.magicIdentityCheck` → `MatrixCalculator.multiply`.
- **Tempo trace diff:** slow traces in both runs are dominated by `/flaky` and `/memory/churn`
  operations (the matrix burn is invoked under `/cpu/magic-identity-check` and is CPU-bound rather
  than I/O-bound, so it does not surface as a long span). Max non-synthetic durations are similar
  between runs (~104-193 ms), consistent with the regression being CPU-time inflation spread across
  many compute sub-requests rather than one slow downstream call.
- **Loki:** no GC/stdout log lines emitted by afterburner-fe in the window (the app does not log
  GC events; JVM GC is observed via the Grafana JVM dashboard metric instead). Log-based analysis
  yielded no additional signal.
- **Dynatrace:** not connected for this run.

## Recommendation

Revert or gate the `funSize` randomisation in `CpuBurner.magicIdentityCheck`. If variability is
desired for demo purposes, bound the multiplier far more tightly (e.g. ±10%) rather than 1x–4x,
because the O(n³) cost makes even a modest dimension increase dominate CPU and GC. Until then this
build should be treated as a confirmed CPU/compute regression versus `2.4.3-good-baseline`.

---
_Generated from Perfana MCP + Grafana (Pyroscope/Tempo/Loki) data. Baseline: PerfanaWebshop-acc-loadTest-00002._
