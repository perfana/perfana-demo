---
name: perf-review
description: >
  Trigger a load test against the local perfana-demo stack, wait for Perfana's Adapt
  engine to complete regression analysis, and output a PASS / REGRESSION / INCONCLUSIVE
  verdict with root cause attribution to a specific Java method.
  Use when a developer says "perf review", "check my changes for regressions",
  "did I introduce a performance regression", "run perf-review cpu/pool/backend/build",
  or "test my afterburner changes".
  Two modes: Mode A uses a pre-built demo variant (cpu/pool/backend/baseline);
  Mode B builds the developer's local afterburner changes via Jib and deploys them.
  Requires Perfana MCP. Grafana MCP and GitNexus MCP improve root cause depth.
context: fork
---

# /perf-review

Runs a load test against the perfana-demo stack and delivers a code-review-style
verdict: did this change introduce a performance regression, which metric, and
which Java method caused it.

**Modes:**
- `/perf-review cpu|pool|backend|baseline` — Mode A: use a pre-built afterburner variant
- `/perf-review build` — Mode B: build the developer's local afterburner source via Jib

**Known SUT_VERSION per Mode A scenario** (set internally by deploy script):
| Scenario | SUT_VERSION | What it tests |
|---|---|---|
| `baseline` | `2.4.3-good-baseline` | Clean reference — use to set a new baseline |
| `cpu` | `2.4.3-changed-matrix-calc` | CPU regression via heavier matrix calculation |
| `pool` | `2.4.3-default-http-conn-pool` | Connection pool exhaustion |
| `backend` | `2.4.3-increased-backend-calls` | Tripled downstream backend calls |

---

## Step 0 — MCP preflight

Check which MCP servers are available. Use `ToolSearch` to probe each.

### Perfana MCP (required)

Search for `mcp__perfana__get_recent_runs`.

- **Found** → Continue.
- **Not found** → **Stop.** Tell the user:
  > "Perfana MCP is not configured. Add it to `.mcp.json`:
  > `npx -y @perfana/mcp` with env `PERFANA_BASE_URL=http://localhost:3001/api` and your API key."

### Grafana MCP (recommended)

Search for `mcp__grafana__list_datasources`.

- **Found** → `grafanaMcpAvailable = true`. Unlocks Tempo, Loki, Pyroscope, dashboard queries.
- **Not found** → `grafanaMcpAvailable = false`. Note: "Grafana MCP not configured — Tempo trace bridge and log queries unavailable. Root cause attribution will be shallower."

If `grafanaMcpAvailable`, discover Tempo and Loki datasource UIDs:
```
grafana:list_datasources  { type: "tempo" }  → store uid as tempoDatasourceUid
grafana:list_datasources  { type: "loki"  }  → store uid as lokiDatasourceUid
```
Set `tempoMcpAvailable = true/false` and `lokiMcpAvailable = true/false` accordingly.

### GitNexus MCP (optional — deepens Java attribution)

Search for `mcp__gitnexus__query`.

- **Found** → `gitNexusAvailable = true`. Enables call-graph traversal from Java method → callers.
- **Not found** → `gitNexusAvailable = false`. Attribution stops at method name from Tempo spans.

### Preflight summary

```
Preflight:
  Perfana MCP : ✓ / ✗  (required)
  Grafana MCP : ✓ / ✗  (Tempo bridge, Loki logs, Pyroscope)
  GitNexus MCP: ✓ / ✗  (Java call-graph attribution)
```

---

## Step 1 — Parse arguments and validate environment

Read the skill argument: `cpu`, `pool`, `backend`, `baseline`, or `build`.

If no argument provided, ask:
> "Which scenario? `cpu` (CPU regression), `pool` (connection pool), `backend` (downstream calls),
> `baseline` (set new baseline), or `build` (test your local changes)?"

**If `baseline` chosen**, warn before proceeding:
> ⚠️ "You chose `baseline`. This establishes a new Perfana baseline — it does not detect regressions.
> Use `cpu`, `pool`, `backend`, or `build` to compare against the existing baseline.
> Continue with baseline? (yes/no)"

**Validate PERFANA_DEMO_PATH:**
```bash
PERFANA_DEMO_PATH="${PERFANA_DEMO_PATH:-$HOME/workspace/perfana-demo}"
[ -d "$PERFANA_DEMO_PATH" ] || echo "ERROR: perfana-demo not found at $PERFANA_DEMO_PATH"
```
If not found: stop with fix instruction.

**Validate stack is running:**
```bash
curl -sf http://localhost:3001/api/health > /dev/null || echo "UNHEALTHY"
curl -sf http://localhost:3000/api/health > /dev/null || echo "UNHEALTHY"
```
If either fails: stop with:
> "perfana-demo stack is not running. Start it with `./start.sh` in `$PERFANA_DEMO_PATH`."

---

## Step 2 — Build (Mode B only)

Skip this step if Mode A (pre-built variant).

**Locate afterburner repo:**
```bash
AFTERBURNER_PATH="${AFTERBURNER_PATH:-$HOME/workspace/afterburner}"
[ -d "$AFTERBURNER_PATH/afterburner-java" ] || echo "ERROR: afterburner-java not found"
```
If not found: stop with fix instruction.

**Capture git state:**
```bash
cd "$AFTERBURNER_PATH"
SHA=$(git rev-parse --short HEAD)
BRANCH=$(git branch --show-current)
SUT_VERSION="${SHA}-jdk21"
```

Tell user: `"Building afterburner@${SHA} (${BRANCH}) → perfana/afterburner:${SUT_VERSION}"`

**Build via Jib (run in background):**
```bash
cd "$AFTERBURNER_PATH" && \
  mvn package jib:dockerBuild \
    -pl afterburner-java -am \
    -Drevision="$SHA" \
    -DskipTests \
    -q
```

Wait for the background task to complete.

If build fails: output INCONCLUSIVE with the Maven error. Stop.

**Verify image exists:**
```bash
docker images --format "{{.Repository}}:{{.Tag}}" | grep "afterburner:${SUT_VERSION}"
```
If not found: INCONCLUSIVE — "Jib build appeared to succeed but image not in local Docker daemon."

---

## Step 3 — Trigger load test

**Set SUT_VERSION for Mode A:**
```
baseline → SUT_VERSION="2.4.3-good-baseline"
cpu      → SUT_VERSION="2.4.3-changed-matrix-calc"
pool     → SUT_VERSION="2.4.3-default-http-conn-pool"
backend  → SUT_VERSION="2.4.3-increased-backend-calls"
```

Tell user: `"Triggering load test: scenario=${SCENARIO}, SUT_VERSION=${SUT_VERSION}. This takes 5-10 min."`

**Run deploy script (run in background):**

Mode A:
```bash
cd "$PERFANA_DEMO_PATH" && ./deploy-and-test-jmeter.sh "$SCENARIO"
```

Mode B:
```bash
cd "$PERFANA_DEMO_PATH" && SUT_VERSION="$SUT_VERSION" ./deploy-and-test-jmeter.sh custom
```

Wait for background task completion. The script manages afterburner container restart,
health checks, JMeter execution, and perfana-cli lifecycle — it exits when the test
run is complete in Perfana.

If the script exits non-zero: INCONCLUSIVE — include the exit code and last lines of output.

---

## Step 4 — Find test run in Perfana

After the deploy script completes, locate the Perfana test run:

```
perfana:get_recent_runs  { systemUnderTest: "PerfanaWebshop",
                           testEnvironment: "acc",
                           workload: "loadTest",
                           limit: 5 }
```

Scan for a run where `version == SUT_VERSION`.

If not found: wait 60 seconds and retry once. If still not found:
output INCONCLUSIVE — "Test run with version `{SUT_VERSION}` not found in Perfana.
The deploy script may not have passed the version to perfana-cli."

Store `testRunId` from the matching run.

**Wait for Adapt analysis to complete:**
```bash
# Poll until consolidated_result.status is not "running"
# max 5 minutes, 30-second intervals
until_done_check: perfana:get_test_run { testRunId }
```

Use a Bash until-loop (run in background is NOT appropriate here — use a short blocking poll):
```bash
for i in $(seq 1 10); do
  sleep 30
  STATUS=$(curl -sf "http://localhost:3001/api/test-run/$testRunId" | jq -r '.status')
  [ "$STATUS" != "running" ] && break
done
```

If still running after 5 minutes: proceed anyway — Adapt results may be partial.

---

## Step 5 — Regression detection

Fetch the core Perfana data in parallel:

```
perfana:get_adapt_results   { testRunId }
perfana:get_check_results   { testRunId }
perfana:get_test_run        { testRunId }
```

**Evaluate verdict:**

- If `get_adapt_results` shows no regressions AND all `get_check_results` SLOs pass:
  → **PASS**. Skip steps 6–8. Go to Step 9 (output).

- If any regression detected or SLO failed:
  → **REGRESSION**. Continue to step 6.

For REGRESSION, fetch in parallel:
```
perfana:get_hotspots      { testRunId }
perfana:get_slow_traces   { testRunId }
perfana:get_flamegraph    { testRunId }
perfana:get_error_analysis { testRunId }
```

---

## Step 6 — Bridge: JMeter transaction → Java method (CRITICAL)

**Why this step exists:** JMeter transaction labels (e.g. `T03_Search_Products`) are
load-test identifiers, not Java method names. This step traverses from metric → trace → span → method.

This step requires `tempoMcpAvailable`. If unavailable, skip to Step 7 and note the gap.

**Get trace IDs** from `get_slow_traces` for the top regressed transaction (highest `change_pct` from `get_adapt_results`).

**Query Tempo for span attributes:**
```
grafana:tempo_traceql-search  {
  datasourceUid: tempoDatasourceUid,
  query: "{ .perfana-request-name =~ \".*<transaction-name>.*\" && duration > 500ms }",
  start: testRunStart,
  end: testRunEnd,
  limit: 10
}
```

For each returned trace, look for span attributes:
- `code.function` → the Java method name (e.g., `AfterburnerController.memoryChurn`)
- `code.namespace` → the Java class (e.g., `io.perfana.afterburner.controller`)
- `http.route` → the Spring MVC route (e.g., `/memory/churn`) — fallback if `code.function` absent
- `db.statement` → SQL query if the bottleneck is database

**Extract the primary Java method:**
- Prefer `code.function` from the deepest span with the highest `duration`
- If `code.function` absent: use `http.route` and note "method inferred from route"

Store as `javaMethod` (e.g., `AfterburnerController.memoryChurn`) and `javaClass`.

---

## Step 7 — Source code context

**Mode B (local build):** Read the source file directly.
```
Read: $AFTERBURNER_PATH/afterburner-java/src/main/java/io/perfana/afterburner/<path>/<ClassName>.java
```
Search for the `javaMethod` in the file. Quote the relevant method body in the verdict.

**Mode A (pre-built variant):** Fetch from GitHub.
```
WebFetch: https://raw.githubusercontent.com/perfana/afterburner/main/src/main/java/io/perfana/afterburner/<path>/<ClassName>.java
```

**GitNexus call-graph (if `gitNexusAvailable`):**
```
gitnexus:query  { query: "<javaMethod>" }
gitnexus:impact { target: "<javaMethod>", direction: "upstream" }
```

Extract:
- Direct callers of `javaMethod`
- Risk level (LOW / MEDIUM / HIGH / CRITICAL)
- Execution flows affected

---

## Step 8 — Supplementary data

Run in parallel (if available):

```
grafana:query_prometheus  {
  expr: "<regressed-metric-promql>",
  start: testRunStart, end: testRunEnd
}
grafana:query_loki_logs  {
  datasourceUid: lokiDatasourceUid,
  logql: "{service_name=\"afterburner-be\"} |= \"ERROR\"",
  startRfc3339: testRunStart, endRfc3339: testRunEnd,
  limit: 50
}
```

Use the regressed metric name from `get_adapt_results` to construct the PromQL expression.

---

## Step 9 — Output verdict

Emit the verdict in this exact format:

```markdown
## Perf Review — {systemUnderTest} @ {SUT_VERSION}

**Verdict: {PASS | REGRESSION | INCONCLUSIVE}**
Adapt analysis: {N} metrics evaluated | SLOs: {passed}/{total}

---

### What regressed
| Metric | Baseline | Current | Delta |
|--------|----------|---------|-------|
| {metric name} | {baseline value} | {current value} | **{delta}** |

(omit this section if PASS)

### Root cause
Transaction `{transactionName}` is the hot path.

**Java method** (from Tempo span `code.function`):
`{javaClass}.{javaMethod}()`

```java
// {ClassName}.java — {methodName}()
{relevant method body, max 10 lines}
```

**Call graph** (GitNexus):
- {caller1} → {javaMethod} (risk: {level})
- {N} upstream callers affected

(omit Call graph section if `gitNexusAvailable = false`)

### SLOs
{list SLO failures, or "All {N} SLOs passed"}

### Recommendation
**{Block | Accept | Investigate}** — {one-sentence reason}

{If REGRESSION}: To accept intentional regression: update the Adapt baseline in Perfana
after confirming the change is expected.

---
[Full Perfana run](http://localhost:4000) · [Flame graph](http://localhost:4040) · Run ID: `{testRunId}`
```

**Save verdict to file:**
```bash
mkdir -p "$AFTERBURNER_PATH/.perf-reviews" 2>/dev/null || true
# Write verdict markdown to .perf-reviews/{SUT_VERSION}.md
```

---

## Error handling

| Situation | Action |
|---|---|
| Stack not running | INCONCLUSIVE — "Run `./start.sh` in perfana-demo" |
| Maven build fails (Mode B) | INCONCLUSIVE — include last 20 lines of Maven output |
| Docker image not found after build | INCONCLUSIVE — "Check Docker daemon is running" |
| Deploy script exits non-zero | INCONCLUSIVE — include exit code |
| Test run not found in Perfana | INCONCLUSIVE — "version tag not found; check perfana-cli --version arg" |
| Adapt still running after 5 min | Proceed with partial data; note "Analysis incomplete" |
| `get_adapt_results` error | Retry once; if still failing, use `get_test_run.consolidated_result` |
| `tempoMcpAvailable = false` | Skip Step 6; note "Tempo unavailable — Java method attribution skipped" |
| Tempo returns no spans with `code.function` | Fall back to `http.route`; note "method inferred from route, not span attribute" |
| `gitNexusAvailable = false` | Skip call-graph section; note "Run `npx gitnexus analyze` in afterburner for deeper attribution" |
| Source file not found | Note "Source file not found at expected path" — output method name from Tempo only |
