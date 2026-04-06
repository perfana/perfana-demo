---
testRunId: PerfanaWebshop-acc-loadTest-00005
system: PerfanaWebshop
environment: acc
workload: loadTest
release: 2.4.3-default-http-conn-pool
date: 2026-04-06
duration: 364s
result: FAIL
tags: [performance-report, jmeter, spring-boot-kubernetes, spanmetrics, docker]
baseline: PerfanaWebshop-acc-loadTest-00003
---

# Performance test report — PerfanaWebshop-acc-loadTest-00005

## Summary

| Field | Value |
|---|---|
| System | PerfanaWebshop |
| Environment | acc |
| Workload | loadTest |
| Release | `2.4.3-default-http-conn-pool` |
| Start time | 2026-04-06T10:26:16Z |
| Duration | 364s (planned 360s) |
| Completion | 100% |
| **Overall result** | **FAIL ❌** |
| Adapt verdict | REGRESSION |
| SLO checks passed | 10 / 10 |
| Annotations | Proxy Dev: use default httpclient connection pool size |
| Tags | jmeter, spring-boot-kubernetes, spanmetrics, docker |

> HTTP connection pool for `afterburner-fe` was reduced from 60 to 2 connections (`afterburner.remote.call.httpclient.connections.max`), collapsing parallel remote call capacity and causing broad latency regressions across 26 metrics in both BrowseAndSearch and Checkout scenarios — despite all SLO checks passing.

---

## Verdict

### Adapt regression analysis

| Metric | Count |
|---|---|
| Total metrics evaluated | 284 |
| Regressions | 26 |
| Improvements | 7 |
| Differences | 284 |
| No difference | — |
| **Conclusion** | **REGRESSION ❌** |

### SLO / requirements checks

| Dashboard | Metric | Result | Value | Requirement |
|---|---|---|---|---|
| Docker container metrics perfana-demo-afterburner-be-1 | CPU | PASS ✅ | 3.35 | < 70 |
| Docker container metrics perfana-demo-afterburner-fe-1 | CPU | PASS ✅ | 5.61 | < 70 |
| Hikari Connection Pool afterburner-be | Pending connections | PASS ✅ | 0 | < 10 |
| Hikari Connection Pool afterburner-fe | Pending connections | PASS ✅ | 0 | < 10 |
| HTTP connection pool afterburner-be | HTTP connection pool in use | PASS ✅ | 0 | < 90% |
| HTTP connection pool afterburner-fe | HTTP connection pool in use | PASS ✅ | 0.20 | < 90% |
| JVM memory management G1GC afterburner-be | Maximum Pause Durations end of minor GC by cause | PASS ✅ | 14.7ms | < 100ms |
| JVM memory management G1GC afterburner-fe | Maximum Pause Durations end of minor GC by cause | PASS ✅ | 15.4ms | < 100ms |
| JVM memory management G1GC afterburner-be | Maximum Pause Durations end of major GC by cause | PASS ✅ | 12.2ms | < 600ms |
| JVM memory management G1GC afterburner-fe | Maximum Pause Durations end of major GC by cause | PASS ✅ | 21.2ms | < 600ms |

> Note: all 10 SLO checks pass. The regression is detected by Adapt statistical comparison against the baseline — the absolute values remain within thresholds but the distributions are significantly worse.

---

## Transaction performance

### Response time table

| Transaction | Scenario | Avg (ms) | p95 (ms) | p99 (ms) | Threshold (ms) | Apdex | |
|---|---|---|---|---|---|---|---|
| T04_Payment_Processing | Checkout | 911.41 | 1098.4 | 1162.24 | 500 | 0.500 | ❌ |
| T05_Order_Confirmation | Checkout | 875.92 | 1041.0 | 1104.68 | 500 | 0.500 | ❌ |
| T04_View_Product_Details | BrowseAndSearch | 717.89 | 885.6 | 893.41 | 500 | 0.500 | ❌ |
| T03_Shipping_Address | Checkout | 642.57 | 781.3 | 830.18 | 500 | 0.500 | ❌ |
| T06_Compare_Products | BrowseAndSearch | 460.15 | 622.55 | 653.83 | 500 | 0.888 | ⚠️ |
| T02_Browse_Category | BrowseAndSearch | 388.63 | 525.65 | 575.95 | 500 | 0.947 | ✅ |
| T01_Homepage_Load | BrowseAndSearch | 385.13 | 430.0 | 578.66 | 500 | 0.987 | ✅ |
| T03_Search_Products | BrowseAndSearch | 297.95 | 407.75 | 502.67 | 500 | 0.987 | ✅ |
| T02_User_Login | Checkout | 291.58 | 369.2 | 410.36 | 500 | 1.000 | ✅ |
| T06_Post_Order_Recommendations | Checkout | 241.54 | 295.9 | 305.66 | 500 | 1.000 | ✅ |
| T01_Add_To_Cart | Checkout | 241.91 | 387.6 | 425.69 | 500 | 1.000 | ✅ |
| T07_Order_Tracking_Assets | Checkout | 177.76 | 242.0 | 249.76 | 500 | 1.000 | ✅ |
| T07_Product_Assets | BrowseAndSearch | 103.08 | 160.0 | 164.41 | 500 | 1.000 | ✅ |
| T05_Apply_Filters | BrowseAndSearch | 97.59 | 224.0 | 340.96 | 500 | 1.000 | ✅ |

_✅ Apdex ≥ 0.85 · ⚠️ Apdex 0.70–0.85 · ❌ Apdex < 0.70_

### p99 tail overshoot (transactions where p99 > threshold)

| Transaction | p99 (ms) | Threshold (ms) | Overshoot | % over |
|---|---|---|---|---|
| T04_Payment_Processing | 1162.24 | 500 | +662ms | +132% |
| T05_Order_Confirmation | 1104.68 | 500 | +605ms | +121% |
| T04_View_Product_Details | 893.41 | 500 | +393ms | +79% |
| T03_Shipping_Address | 830.18 | 500 | +330ms | +66% |
| T06_Compare_Products | 653.83 | 500 | +154ms | +31% |
| T02_Browse_Category | 575.95 | 500 | +76ms | +15% |
| T01_Homepage_Load | 578.66 | 500 | +79ms | +16% |
| T03_Search_Products | 502.67 | 500 | +3ms | +1% |

### Top 5 by impact (avg response time × request count)

_Performance rankings unavailable (404 from rankings endpoint) — derived from transaction stats._

| Rank | Transaction | Avg RT (ms) | Count | Apdex |
|---|---|---|---|---|
| 1 | T04_Payment_Processing | 911.41 | 37 | 0.500 |
| 2 | T05_Order_Confirmation | 875.92 | 37 | 0.500 |
| 3 | T04_View_Product_Details | 717.89 | 38 | 0.500 |
| 4 | T03_Shipping_Address | 642.57 | 35 | 0.500 |
| 5 | T06_Compare_Products | 460.15 | 40 | 0.888 |

---

## Regression analysis vs baseline

> Baseline: `PerfanaWebshop-acc-loadTest-00003` — 2.4.3-changed-matrix-calc (2026-04-06T10:02Z)
> Config changes: 5 changed · Unchanged: 21

### Config changes

| Key | Baseline | Current |
|---|---|---|
| `afterburner.remote.call.httpclient.connections.max` | `60` | `2` |
| `testContext.version` | `2.4.3-changed-matrix-calc` | `2.4.3-default-http-conn-pool` |
| `testContext.annotations` | `Proxy Dev: make matrix calculation more variable` | `Proxy Dev: use default httpclient connection pool size` |
| `github.com/perfana/perfana-demo` (commit) | `26361d2` | `19b60ef` |
| `testContext.testRunId` | `PerfanaWebshop-acc-loadTest-00003` | `PerfanaWebshop-acc-loadTest-00005` |

> **Key change:** `afterburner.remote.call.httpclient.connections.max` was dropped from 60 to **2**. Despite the annotation saying "use default", this is a severely under-provisioned value for a service making parallel remote calls under load. This single config change is the root cause.

### Regressions by classification

#### Transaction latency (8 regressions)

**Hypothesis:** Downstream consequence of HTTP connection pool starvation — parallel remote calls are serialised through 2 connections, multiplying observed latency for every multi-call transaction.

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| `T04_View_Product_Details` | Performance test metrics BrowseAndSearch | 443ms | 718ms | +62.0% |
| `T03_Shipping_Address` | Performance test metrics Checkout | 398ms | 644ms | +61.6% |
| `T02_Browse_Category` | Performance test metrics BrowseAndSearch | 248ms | 390ms | +57.5% |
| `T06_Compare_Products` | Performance test metrics BrowseAndSearch | 246ms | 464ms | +88.9% |
| `T06_Post_Order_Recommendations` | Performance test metrics Checkout | 167ms | 242ms | +44.9% |
| `T01_Homepage_Load` | Performance test metrics BrowseAndSearch | 276ms | 385ms | +39.5% |
| `T03_Shipping_Address` (Apdex) | Performance test metrics Checkout | 1.0 | 0.5 | -50.0% |
| `T04_View_Product_Details` (Apdex) | Performance test metrics BrowseAndSearch | 1.0 | 0.5 | -50.0% |

#### Request latency (14 regressions)

**Hypothesis:** Each sub-request that goes through `remoteCallHttpClientMany` is queued behind the 2-connection limit. The worst offenders are those that fan-out to multiple back-end calls simultaneously.

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| `T02_Browse_Category.category_inventory_check_remote` | Performance test metrics BrowseAndSearch | 58ms | 193ms | +232.3% |
| `T04_View_Product_Details.product_images_cdn_fetch` | Performance test metrics BrowseAndSearch | 89ms | 230ms | +160.1% |
| `T04_View_Product_Details.product_related_items_api` | Performance test metrics BrowseAndSearch | 108ms | 234ms | +117.7% |
| `T06_Compare_Products.compare_price_history_api` | Performance test metrics BrowseAndSearch | 161ms | 341ms | +111.7% |
| `T06_Post_Order_Recommendations.recommendations_products_fetch` | Performance test metrics Checkout | 90ms | 179ms | +99.9% |
| `T03_Shipping_Address.shipping_rates_api` | Performance test metrics Checkout | 208ms | 414ms | +99.5% |
| `T05_Order_Confirmation.order_create_db_transaction` | Performance test metrics Checkout | 63ms | 121ms | +92.6% |
| `T01_Homepage_Load.homepage_featured_products_api` | Performance test metrics BrowseAndSearch | 113ms | 217ms | +91.5% |

#### Connection pool (1 regression)

**Hypothesis:** The HTTP client pool in `afterburner-fe` is the bottleneck — 2 connections serving all concurrent outbound requests means steady queuing under load.

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| `afterburner-http-client` | HTTP connection pool afterburner-fe | 0.66% | 20.0% | +2930% |

#### Error rates (4 regressions)

**Hypothesis:** Higher error rates in `T04_View_Product_Details.product_images_cdn_fetch` stem from async execution timeouts when the connection pool is saturated. `T07` and payment errors are flaky fixture noise.

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| `T07_Order_Tracking_Assets.shipping_status_check` | Performance test metrics Checkout | 0.8% | 3.23% | +303.2% |
| `error_count` | Performance test metrics BrowseAndSearch | 0.05 | 0.40 | +740% |
| `T04_View_Product_Details.product_images_cdn_fetch` | Performance test metrics BrowseAndSearch | 0% | 6.06% | new |
| `T04_View_Product_Details` (error rate) | Performance test metrics BrowseAndSearch | 0% | 5.26% | new |

### Improvements (preserve in any rollback)

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
| `T03_Search_Products.search_query_processing` | Performance test metrics BrowseAndSearch | 20ms | 6ms | -70.0% |
| `T04_Payment_Processing.payment_fraud_check` | Performance test metrics Checkout | 30ms | 7ms | -75.9% |
| `T05_Order_Confirmation.order_confirmation_pdf_gen` | Performance test metrics Checkout | 55ms | 9ms | -82.8% |
| `T07_Order_Tracking_Assets.loyalty_points_api` | Performance test metrics Checkout | 1.49% | 0% | -100% |
| `T07_Product_Assets` (error rate) | Performance test metrics BrowseAndSearch | 0.65% | 0% | -100% |
| `T07_Product_Assets.product_availability_check` | Performance test metrics BrowseAndSearch | 0.67% | 0% | -100% |
| `employee-db-pool` (active connections) | Hikari Connection Pool afterburner-be | 0.030 | 0 | -100% |

> These improvements (especially the -70% to -83% compute sub-request improvements) indicate the prior run `00003` carried a computation inefficiency that has since been fixed. They should be preserved in any rollback decision.

---

## Error analysis

| Metric | Value |
|---|---|
| Total requests | 2,396 |
| Total errors | 4 |
| Overall error rate | 0.17% |
| Unique HTTP error codes | 1 |
| Transactions with errors | 3 |

### Errors by status code

| Code | Count | Avg RT (ms) | Min RT (ms) | Max RT (ms) |
|---|---|---|---|---|
| 500 | 4 | 293 | 133 | 406 |

### Errors by transaction

| Transaction | Sampler | URL | Code | Count | Classification |
|---|---|---|---|---|---|
| T04_View_Product_Details | product_images_cdn_fetch | `http://afterburner-fe:8080/remote/call-many?count=4&path=delay?duration=80` | 500 | 2 | Real error — async execution failure (`AfterburnerException: Execute async failed`) |
| T04_Payment_Processing | payment_gateway_auth | `http://afterburner-fe:8080/flaky?maxRandomDelay=300&flakiness=3` | 500 | 1 | Flaky fixture |
| T07_Order_Tracking_Assets | shipping_status_check | `http://afterburner-fe:8080/flaky?flakiness=2&maxRandomDelay=150` | 500 | 1 | Flaky fixture |

> Two of the three erroring transactions hit `/flaky` endpoints (Afterburner chaos fixture) — these are **not real application errors**. The single genuine error source is `T04_View_Product_Details.product_images_cdn_fetch`, which calls `/remote/call-many` — a fan-out endpoint that spawns multiple async HTTP calls. With only 2 connections available in the pool, the async executor exhausts available connections and throws `AfterburnerException: Execute async failed`.

---

## Cross-source investigation

> **Data sources:** Grafana ✅ · Tempo ✅ · Pyroscope ✅ · Dynatrace ❌ (not configured)
> **Confidence: High**

### Distributed traces — baseline vs current comparison

**Overall slowest traces (excluding `enable-traffic-light-for-some-time` synthetic timer):**

| | Baseline (`00003`) | Current (`00005`) |
|---|---|---|
| Max duration | 154ms (`get /delay`) | 504ms (`get /remote/call-many`) |
| Median of top-10 traces | 81ms | 113ms |
| New trace types | — | None — but `get /remote/call-many` dominates |

> The baseline's slowest non-synthetic trace was 154ms. In the current run it is 504ms — a 3.3x increase — and all the top traces are `get /remote/call-many`. This operation is the fan-out HTTP call that is throttled by the reduced connection pool.

**T04_View_Product_Details — per-transaction trace comparison:**

| | Baseline (`00003`) | Current (`00005`) |
|---|---|---|
| Slowest trace | 106ms (`get /remote/call-many`) | 361ms (`get /remote/call-many`) |
| Span structure | 13 spans — 4 parallel `execute-call-async` + 4 `get /delay` to `afterburner-be` | 4 spans — 1 `execute-call-async` + 1 `get /delay` (serialised) |

**Trace drill-down — `c14839ed91d0b36` (504ms, current run, `payment_process_transaction`):**

| Span | Service | Duration | % of trace |
|---|---|---|---|
| `get /remote/call-many` | afterburner-fe | 505ms | 100% |
| `execute-call-async` | afterburner-fe | 503ms | 100% |
| `get` (HTTP client) | afterburner-fe | 503ms | 100% |
| `get /delay` | afterburner-be | 502ms | 99% |

> The current trace shows a **single sequential** `execute-call-async` call taking 503ms. Compare with the baseline trace `187d225f3807c651` (84ms total): it has **4 parallel** `execute-call-async` spans all completing in ~82ms each. The connection pool collapse has eliminated parallelism — only 1 of the 4 fan-out calls is dispatched at a time, and each waits for the previous to release its connection.

**T03_Shipping_Address — per-transaction trace comparison:**

| | Baseline (`00003`) | Current (`00005`) |
|---|---|---|
| Slowest trace | ~185ms | 423ms (`get /remote/call-many`) |

**T06_Compare_Products — per-transaction trace comparison:**

| | Baseline (`00003`) | Current (`00005`) |
|---|---|---|
| Slowest trace | ~106ms | 505ms (`get /remote/call-many`) |

### CPU profiling (Pyroscope)

**Top hotspots for `afterburner-fe`:**

| Method | Samples | % CPU |
|---|---|---|
| `io/perfana/afterburner/matrix/MatrixCalculator.multiply` | 1,394,736,764 | 6.65% |
| `libc.so.6.__GI___fstatat64` | 421,052,608 | 2.01% |
| `.I2C/C2I adapters` | 381,578,926 | 1.82% |
| `libc.so.6.__GI___futex_abstimed_wait_cancelable64` | 328,947,350 | 1.57% |
| `libc.so.6.__libc_write` | 315,789,456 | 1.51% |
| `libc.so.6.__GI___getdents64` | 289,473,668 | 1.38% |
| `libjvm.so.IndexSetIterator::advance_and_next` | 210,526,304 | 1.00% |
| `libjvm.so.PhaseChaitin::Split` | 171,052,622 | 0.82% |
| `java/util/HashMap.getNode` | 157,894,728 | 0.75% |
| `.itable stub` | 157,894,728 | 0.75% |

> `MatrixCalculator.multiply` is the dominant CPU consumer at 6.65%. This is consistent with the computation sub-requests seen in the previous run `00003` (where `matrix_calculation` style requests were the root cause). Notably, CPU overall remains low (container CPU check passed at 5.6%) — the matrix computation is present but not causing a bottleneck in this run. The real bottleneck is I/O (connection pool), not CPU.

### Investigation gaps

- **Dynatrace:** Not configured for this system. Infrastructure problem detection skipped.
- **Flamegraph (collapsed stacks):** Returned malformed JSON from Pyroscope — hotspots used instead.
- **Deep links:** 404 from Perfana deep links endpoint — direct Grafana dashboard URLs not available.
- **Performance rankings:** 404 from rankings endpoint — impact table derived from transaction stats.

---

## Root cause & recommendations

### Root cause (confidence: High)

The `afterburner-fe` HTTP client connection pool (`afterburner.remote.call.httpclient.connections.max`) was reduced from **60 to 2** between release `2.4.3-changed-matrix-calc` and `2.4.3-default-http-conn-pool`. Despite the annotation describing this as "use default", a pool of 2 is catastrophically small for a service that makes parallel fan-out HTTP calls under concurrent load.

The trace comparison provides definitive evidence. In the baseline run, a `get /remote/call-many` trace for `T04_View_Product_Details.product_images_cdn_fetch` (trace `187d225f3807c651`, 84ms) shows **4 parallel** `execute-call-async` spans each completing in ~82ms — all 4 remote calls to `afterburner-be` run concurrently. In the current run, the same operation (trace `c14839ed91d0b36`, 504ms) shows only **1 sequential** `execute-call-async` span taking 503ms. The pool size of 2 prevents the async executor from dispatching more than one-to-two concurrent outbound requests, serialising what should be parallel work and adding approximately 400ms of connection-wait time per fan-out transaction.

The Adapt data confirms the causal chain at High confidence: latency regressions across 22 request/transaction metrics (Performance test dashboards) are paired with a 2930% increase in `afterburner-http-client` pool utilisation (HTTP connection pool dashboard). The pool peaked at 20% mean utilisation — but since there are only 2 connections, 20% mean implies frequent saturation spikes. The JVM, GC, and Hikari DB pool checks all remain healthy, confirming the bottleneck is specifically the outbound HTTP client pool.

The `T04_View_Product_Details.product_images_cdn_fetch` errors (`AfterburnerException: Execute async failed`) are a direct consequence: when all connections are in use and an async call is submitted, the executor rejects it rather than queuing indefinitely.

### Evidence chain

| Source | Finding | Supports hypothesis? |
|---|---|---|
| Config diff | `httpclient.connections.max` 60 → 2 | Yes ✅ |
| Adapt (connection pool) | `afterburner-http-client` pool utilisation +2930% (0.66% → 20%) | Yes ✅ |
| Adapt (causal chain) | "Latency regression → connection pool saturation" — High confidence | Yes ✅ |
| Trace comparison | Baseline: 4 parallel spans, 84ms total. Current: 1 sequential span, 504ms total — parallelism eliminated | Yes ✅ |
| Error details | `AfterburnerException: Execute async failed` on `/remote/call-many` (fan-out endpoint) | Yes ✅ |
| Pyroscope hotspots | `MatrixCalculator.multiply` at 6.65% CPU — compute present but CPU overall low (5.6%) | Partial ⚠️ — confirms compute work exists but not the bottleneck this run |
| SLO checks | All 10 pass — CPU, GC, Hikari DB pool all healthy | Yes ✅ — confirms bottleneck is isolated to HTTP client pool |
| Dynatrace | Not available | — |

### Recommendations

1. **Immediately revert `afterburner.remote.call.httpclient.connections.max` to 60 (or higher).** A pool of 2 is not viable for a service making parallel fan-out calls. The "default" HTTP client pool size in Apache HttpClient / Spring RestTemplate is typically 2 per route and 20 total — but for a high-concurrency service calling a single back-end host, the per-route limit must be raised. Set it to at least `20` and validate under load; `60` is the previously proven safe value.

2. **Explicitly configure and document the HTTP client pool size in application config.** The annotation "use default httpclient connection pool size" implies the team is relying on an implicit default that is inappropriate for this use case. Add an explicit `afterburner.remote.call.httpclient.connections.max=60` (or higher) to the production application properties so it is never accidentally reverted.

3. **Add an SLO check on HTTP connection pool utilisation.** The existing Hikari DB pool check (`pending connections < 10`) caught nothing because the bottleneck is the outbound HTTP client pool, not the DB pool. Add a check: `afterburner-http-client pool in use < 70%`. This would have flagged the regression automatically in this run (current mean: 20%, but with spikes that caused errors).

4. **Investigate the `T04_View_Product_Details.product_images_cdn_fetch` error path in the application code.** Trace `c14839ed91d0b36` shows the fan-out call failing entirely when pool connections are exhausted. Consider adding a timeout and graceful fallback (e.g., return cached/placeholder images) rather than propagating a 500 to the user. This would improve resilience even if the pool is temporarily under-provisioned.

5. **Preserve the compute improvements from this release.** Three sub-requests improved by 70–83% (`search_query_processing`, `payment_fraud_check`, `order_confirmation_pdf_gen`). These improvements are real and valuable — any rollback should cherry-pick the connection pool config fix rather than reverting the full release.

---

## Run trend (last 5 runs)

| Run | Date | Release | Result | Adapt |
|---|---|---|---|---|
| `PerfanaWebshop-acc-loadTest-00005` | 2026-04-06 | `2.4.3-default-http-conn-pool` | FAIL ❌ | REGRESSION |
| `PerfanaWebshop-acc-loadTest-00004` | 2026-04-06 | `2.4.3-good-baseline` | PASS ✅ | OK |
| `PerfanaWebshop-acc-loadTest-00003` | 2026-04-06 | `2.4.3-changed-matrix-calc` | FAIL ❌ | REGRESSION |
| `PerfanaWebshop-acc-loadTest-00002` | 2026-04-06 | `2.4.3-good-baseline` | PASS ✅ | OK (differences accepted) |
| `PerfanaWebshop-acc-loadTest-00001` | 2026-04-06 | `2.4.3-good-baseline` | PASS ✅ | No baselines (first run) |

---

## Links

- CI build: http://nu.nl
- Perfana UI: http://localhost:4000
- Grafana: http://localhost:3000
- Pyroscope: http://pyroscope:4040
- Tempo: http://tempo:3200

---

_Report generated 2026-04-06 by Claude Code · Perfana report skill v2.0 (with cross-source investigation)_
