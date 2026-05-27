# Performance test report template

Fill all `{{placeholders}}` from fetched Perfana data. Write `_No data available_` for
any section with no data — never leave placeholder text in the output.

````markdown
---
testRunId: {{testRunId}}
system: {{systemUnderTest}}
environment: {{testEnvironment}}
workload: {{workload}}
release: {{applicationRelease}}
date: {{startTime | YYYY-MM-DD}}
duration: {{durationSeconds}}s
result: {{PASS or FAIL}}
tags: [performance-report, {{csvTags}}]
baseline: {{baselineRunId}}
---

# Performance test report — {{testRunId}}

## Summary

| Field | Value |
|---|---|
| System | {{systemUnderTest}} |
| Environment | {{testEnvironment}} |
| Workload | {{workload}} |
| Release | `{{applicationRelease}}` |
| Start time | {{startTime}} |
| Duration | {{durationSeconds}}s (planned {{plannedDuration}}s) |
| Completion | {{completionPct}}% |
| **Overall result** | **{{PASS ✅ or FAIL ❌}}** |
| Adapt verdict | {{adaptConclusion}} |
| SLO checks passed | {{sloPassCount}} / {{sloTotalCount}} |
| Annotations | {{annotations}} |
| Tags | {{csvTags}} |

> {{oneLineSummary}}

---

## Verdict

### Adapt regression analysis

| Metric | Count |
|---|---|
| Total metrics evaluated | {{totalResults}} |
| Regressions | {{regressionCount}} |
| Improvements | {{improvementCount}} |
| Differences | {{differenceCount}} |
| No difference | {{noDifferenceCount}} |
| **Conclusion** | **{{adaptConclusion}}** |

### SLO / requirements checks

| Dashboard | Metric | Result | Value | Requirement |
|---|---|---|---|---|
{{for each sloCheck}}
| {{dashboard_label}} | {{panel_title}} | {{PASS ✅ or FAIL ❌}} | {{panel_average}} | {{requirement summary}} |
{{end}}

---

## Transaction performance

### Response time table

| Transaction | Scenario | Avg (ms) | p95 (ms) | p99 (ms) | Threshold (ms) | Apdex | |
|---|---|---|---|---|---|---|---|
{{for each transaction sorted by apdex asc}}
| {{transaction_name}} | {{scenario_name}} | {{avg_response_time}} | {{p95_response_time}} | {{p99_response_time}} | {{active_threshold}} | {{apdex_score}} | {{✅ ⚠️ or ❌}} |
{{end}}

_✅ Apdex ≥ 0.85 · ⚠️ Apdex 0.70–0.85 · ❌ Apdex < 0.70_

### p99 tail overshoot (transactions where p99 > threshold)

| Transaction | p99 (ms) | Threshold (ms) | Overshoot | % over |
|---|---|---|---|---|
{{for each transaction where p99 > threshold, sorted by overshoot desc}}
| {{transaction_name}} | {{p99}} | {{threshold}} | +{{overshoot}}ms | +{{pct}}% |
{{end}}

### Top 5 by impact score

| Rank | Transaction | Avg RT (ms) | Count | Impact | Apdex |
|---|---|---|---|---|---|
{{for rank 1..5 from highest_impact ranking}}
| {{rank}} | {{transaction_name}} | {{avg_response_time_ms}} | {{total_count}} | {{impact}} | {{apdex_score}} |
{{end}}

---

## Regression analysis vs baseline

> Baseline: `{{baselineRunId}}` — {{baselineRelease}} ({{baselineDate}})
> Config changes: {{configChangedCount}} · Unchanged: {{configUnchangedCount}}

{{if configChanges}}
### Config changes

| Key | Baseline | Current |
|---|---|---|
{{for each configChange}}
| `{{key}}` | {{baseline}} | {{current}} |
{{end}}
{{else}}
All {{configUnchangedCount}} config items are **identical**. The regression is
attributable solely to the code change.
{{end}}

### Regressions by classification

{{for each classificationGroup with regressions}}
#### {{groupName}} ({{count}} regressions)

**Hypothesis:** {{hypothesis}}

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
{{for top 8 regressions in group, sorted by |change_pct| desc}}
| `{{metric_name}}` | {{dashboard}} | {{baseline}}{{unit}} | {{current}}{{unit}} | {{change_pct}}% |
{{end}}

{{end}}

### Improvements (preserve in any rollback)

| Metric | Dashboard | Baseline | Current | Change |
|---|---|---|---|---|
{{for each improvement}}
| `{{metric_name}}` | {{dashboard}} | {{baseline}}{{unit}} | {{current}}{{unit}} | {{change_pct}}% |
{{end}}

---

## Error analysis

| Metric | Value |
|---|---|
| Total requests | {{totalRequests}} |
| Total errors | {{totalErrors}} |
| Overall error rate | {{errorRatePct}}% |
| Unique HTTP error codes | {{uniqueResponseCodes}} |
| Transactions with errors | {{transactionsWithErrors}} |

### Errors by status code

| Code | Count | Avg RT (ms) | Min RT (ms) | Max RT (ms) |
|---|---|---|---|---|
{{for each errorByCode}}
| {{responseCode}} | {{errorCount}} | {{avgResponseTime}} | {{minResponseTime}} | {{maxResponseTime}} |
{{end}}

### Errors by transaction

| Transaction | Sampler | URL | Code | Count | Classification |
|---|---|---|---|---|---|
{{for each topError}}
| {{transactionName}} | {{samplerName}} | `{{url}}` | {{responseCode}} | {{errorCount}} | {{Flaky fixture or Real error}} |
{{end}}

{{if allErrorsAreFlaky}}
> All errors originate from `/flaky` endpoints (Afterburner chaos fixture).
> These are **not real application errors** — classify as test infrastructure noise.
{{end}}

---

## Cross-source investigation

> **Data sources:** Grafana {{✅ or ❌}} · Tempo {{✅ or ❌}} · Pyroscope {{✅ or ❌}} · Dynatrace {{✅ or ❌}}
> **Confidence:** {{High / Medium / Low}}

{{if no sources connected}}
_No external data sources connected — investigation based on Perfana metrics only._
{{end}}

{{if tempo available and traces found}}
### Distributed traces — baseline vs current comparison

{{if baseline traces available}}
**Overall slowest traces (excluding synthetic timers):**

| | Baseline ({{baselineRunId}}) | Current ({{testRunId}}) |
|---|---|---|
| Max duration | {{baselineMaxDuration}}ms (`{{baselineMaxOp}}`) | {{currentMaxDuration}}ms (`{{currentMaxOp}}`) |
| Median of top traces | {{baselineMedian}}ms | {{currentMedian}}ms |
| New trace types | — | {{newOperationTypes or "none"}} |

> {{broadTraceDiffInsight — 1-2 sentences: how the overall trace profile shifted}}

{{for each regressed transaction with per-transaction trace diff}}
**{{transactionName}} — per-transaction trace comparison:**

| | Baseline ({{baselineRunId}}) | Current ({{testRunId}}) |
|---|---|---|
| Slowest trace | {{baselineSlowest}}ms (`{{baselineSlowOp}}`) | {{currentSlowest}}ms (`{{currentSlowOp}}`) |
{{if new trace types in current}}
| New trace type | — | {{newDuration}}ms `{{newOp}}` ({{subRequestName}}) |
{{end}}

{{if traceDetail investigated for this transaction}}
**Trace drill-down** — `{{traceId}}` ({{durationMs}}ms, {{whichRun}}, `{{subRequestName}}`):

| Span | Service | Duration | % of trace |
|---|---|---|---|
{{for top 5 spans by duration}}
| {{operationName}} | {{serviceName}} | {{durationMs}}ms | {{pctOfTrace}}% |
{{end}}

> {{perTransactionTraceInsight — note span attributes like matrix-size, batch-count.
  Compare with baseline: what spans are new? What shifted from I/O-bound to CPU-bound?}}
{{end}}
{{end}}
{{else}}
**Slowest traces** (top {{traceCount}}):

| Trace ID | Duration | Root service | Root operation |
|---|---|---|---|
{{for each slowTrace}}
| `{{traceId}}` | {{durationMs}}ms | {{rootServiceName}} | {{rootTraceName}} |
{{end}}

{{if traceDetail investigated}}
**Trace drill-down** — `{{traceId}}` ({{durationMs}}ms):

| Span | Service | Duration | % of trace |
|---|---|---|---|
{{for top 5 spans by duration}}
| {{operationName}} | {{serviceName}} | {{durationMs}}ms | {{pctOfTrace}}% |
{{end}}

> {{traceInsight — 1-2 sentences: what the trace breakdown reveals}}
{{end}}
{{end}}

{{if errorTraces found}}
**Error traces** ({{errorTraceCount}} errors):

| Trace ID | Duration | Service | Error |
|---|---|---|---|
{{for each errorTrace, max 5}}
| `{{traceId}}` | {{durationMs}}ms | {{rootServiceName}} | {{rootTraceName}} |
{{end}}
{{end}}
{{end}}

{{if pyroscope available and hotspots found}}
### CPU profiling (Pyroscope)

**Top hotspots** for `{{serviceName}}`:

| Method | Samples | % CPU |
|---|---|---|
{{for each hotspot, top 10}}
| `{{function}}` | {{samples}} | {{percentage}}% |
{{end}}

> {{flamegraphInsight — 1-2 sentences: what the CPU profile reveals}}
{{end}}

{{if dynatrace available}}
### Infrastructure problems (Dynatrace)

{{if problems found}}
| Problem | Severity | Status | Duration | Affected |
|---|---|---|---|---|
{{for each problem}}
| {{title}} | {{severityLevel}} | {{status}} | {{startTime}} – {{endTime}} | {{affectedEntities}} |
{{end}}
{{else}}
_No Dynatrace problems detected during the test window — infrastructure was healthy._
{{end}}
{{end}}

{{if grafana dashboard snapshots}}
### Dashboard snapshots

{{for each snapshot}}
**{{dashboardName}}:**

| Panel | Metric | Avg | Min | Max | Last |
|---|---|---|---|---|---|
{{for each panel and metric}}
| {{panelTitle}} | `{{metricName}}` | {{avg}} | {{min}} | {{max}} | {{last}} |
{{end}}
{{end}}
{{end}}

{{if any source was unavailable}}
### Investigation gaps

{{for each unavailable source}}
- **{{sourceName}}:** {{reason why unavailable or empty}}
{{end}}
{{end}}

---

## Root cause & recommendations

### Root cause (confidence: {{High / Medium / Low}})

{{rootCauseNarrative — 2-4 paragraphs:
  1. What regressed (from Adapt/SLO checks)
  2. Investigation evidence (from traces, flamegraph, Dynatrace)
  3. Correlation across sources (which evidence points agree)
  4. Most likely cause with confidence level and reasoning}}

### Evidence chain

| Source | Finding | Supports hypothesis? |
|---|---|---|
{{for each piece of evidence used}}
| {{source: Adapt/Traces/Flamegraph/Dynatrace/Config}} | {{one-line finding}} | {{Yes ✅ / Partial ⚠️ / No ❌}} |
{{end}}

### Recommendations

{{Generate 3-5 specific recommendations based on the investigation evidence.
When investigation data is available, recommendations should be concrete:
"Profile method X" instead of "Profile the compute hotspot".
"Investigate trace abc123 showing 2.1s in OrderService" instead of generic advice.}}

1. {{recommendation 1 — most impactful action}}
2. {{recommendation 2}}
3. {{recommendation 3}}
{{if more}} 4-5. {{additional recommendations}} {{end}}

---

## Run trend (last {{recentRunCount}} runs)

| Run | Date | Release | Result | Adapt |
|---|---|---|---|---|
{{for each recentRun}}
| `{{testRunId}}` | {{startDate}} | {{applicationRelease}} | {{PASS ✅ or FAIL ❌}} | {{adaptConclusion}} |
{{end}}

---

## Links

{{for each deepLink}}
- [{{name}}]({{url}})
{{end}}
- [CI build]({{ciBuildResultsUrl}})]

---

_Report generated {{reportTimestamp}} by Claude Code · Perfana report skill v2.0 (with cross-source investigation)_
````
