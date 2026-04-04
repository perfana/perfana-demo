# Perfana Claude Code Skill & MCP Server

This guide explains how to set up the Perfana MCP server and the `perfana-report` Claude Code skill so you can analyse performance test runs and generate reports directly from Claude Code.

## Prerequisites

- [Claude Code](https://claude.ai/code) installed
- Perfana running (locally via this demo or on a remote instance)
- [Obsidian](https://obsidian.md) with the [Local REST API](https://github.com/coddingtonbear/obsidian-local-rest-api) plugin (for report writing)

## 1. Set up the Perfana MCP Server

The MCP server exposes Perfana test run data to Claude Code (or any MCP-compatible client).

### Build the MCP server

From the main Perfana repository:

```bash
cd apps/mcp
npm install
npm run build
```

### Get a Perfana API key

1. Open the Perfana UI (http://localhost:4000)
2. Go to **Settings > API Keys**
3. Generate a new API key

### Configure Claude Code

Add the Perfana MCP server to your Claude Code settings. You can add it at the project level (`.claude/settings.local.json`) or globally (`~/.claude/settings.json`):

```json
{
  "mcpServers": {
    "perfana": {
      "command": "node",
      "args": ["/absolute/path/to/perfana/apps/mcp/dist/index.js"],
      "env": {
        "PERFANA_API_URL": "http://localhost:3001/api",
        "PERFANA_API_KEY": "<your-perfana-api-key>"
      }
    }
  }
}
```

Replace `/absolute/path/to/perfana` with the actual path to your Perfana repository.

### Available MCP tools

| Tool | Description |
|---|---|
| `get_test_run` | Metadata, status, and configuration for a test run |
| `get_transaction_stats` | Response times (avg/p50/p90/p95/p99), throughput, error rates, Apdex scores |
| `get_recent_runs` | Recent runs for a SUT/environment/workload |
| `compare_runs` | Side-by-side regression diff between two runs |
| `get_config_diff` | Diff configuration items between two runs |
| `get_check_results` | SLO / requirements check results |
| `get_adapt_results` | ADAPT regression analysis with severity and confidence |
| `get_deep_links` | Resolved dashboard/tool links for a test run |
| `get_performance_rankings` | Rankings by slowest, highest impact, or highest error rate |
| `get_error_analysis` | Error rates by status code and transaction |
| `get_error_details` | Detailed error information per transaction |
| `list_connected_sources` | Discover connected data sources (Grafana, Tempo, Pyroscope, Dynatrace) |
| `get_slow_traces` | Slow distributed traces from Tempo |
| `get_error_traces` | Error traces from Tempo |
| `get_flamegraph` | CPU flamegraph from Pyroscope |
| `get_hotspots` | CPU hotspot analysis from Pyroscope |
| `get_dynatrace_problems` | Problems detected by Dynatrace during the test window |

## 2. Install the perfana-report Skill

The `perfana-report` skill automates the full workflow of analysing a test run and generating a structured Markdown report.

### Copy the skill into your project

Copy the skill directory from the Perfana repository into your project's `.claude/skills/` directory:

```bash
mkdir -p .claude/skills
cp -r /path/to/perfana/.claude/skills/perfana-report .claude/skills/
```

The resulting structure should be:

```
.claude/skills/perfana-report/
  SKILL.md                              # Skill definition (steps, error handling)
  README.md                             # Skill documentation
  references/
    classification-rules.md             # Regression classification table
    investigation-playbook.md           # Maps hypotheses to MCP tool calls
    report-template.md                  # Markdown report template
    obsidian-api.md                     # Obsidian Local REST API reference
```

Claude Code automatically discovers skills in the `.claude/skills/` directory. Verify it's loaded by checking that `perfana-report` appears in the skill list (`/skills`).

### Set up Obsidian Local REST API

The skill writes reports directly to an Obsidian vault:

1. Open Obsidian
2. Go to **Settings > Community Plugins > Browse**
3. Search for **Local REST API** and install it
4. Enable the plugin
5. In the plugin settings, enable **Enable Insecure Server** (HTTP on port 27123)

The skill reads the API key automatically from:
```
{vaultRoot}/.obsidian/plugins/obsidian-local-rest-api/data.json
```

## 3. Usage

Trigger the skill with natural language in Claude Code:

```
analyse test run PerfanaWebshop-acc-loadTest-00009
```

```
generate a report for the latest load test
```

```
why did performance regress in PerfanaWebshop-acc-loadTest-00012?
```

```
compare run 00012 against baseline 00009
```

Other trigger phrases: "generate a Perfana report", "write a performance test report", "find root cause", "investigate regression".

### What the skill does

1. Fetches all Perfana data (transactions, SLO checks, ADAPT regressions, errors, rankings)
2. Automatically finds a baseline run for comparison
3. Classifies regressions (computation, latency, GC, connection pool, errors, etc.)
4. Investigates root causes across connected data sources (Tempo traces, Pyroscope flamegraphs, Dynatrace problems, Grafana dashboards)
5. Correlates evidence across sources and assigns confidence levels (High/Medium/Low)
6. Generates a standardised Markdown report
7. Writes the report to Obsidian at `Performance Reports/{testRunId}.md`

### Report sections

- **Summary** -- system, environment, workload, duration, overall result
- **Verdict** -- ADAPT regression analysis, SLO check results
- **Transaction performance** -- response times, Apdex scores, p99 tail overshoot, impact ranking
- **Regression analysis** -- classified regressions with hypotheses, config diff vs baseline
- **Error analysis** -- error rates by status code and transaction, flaky endpoint detection
- **Cross-source investigation** -- trace drill-downs, CPU profiling hotspots, Dynatrace problems
- **Root cause & recommendations** -- evidence chain, confidence level, actionable next steps
- **Run trend** -- recent run history for the same SUT/environment/workload

## Customisation

| File | Purpose |
|---|---|
| `references/report-template.md` | Change the report structure and sections |
| `references/classification-rules.md` | Add custom regression classifications |
| `references/investigation-playbook.md` | Add new data source integrations |
