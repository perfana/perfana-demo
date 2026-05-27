# Perfana Report Skill

A Claude Code skill that analyses Perfana performance test runs and generates comprehensive Markdown reports. Reports can be written to an Obsidian vault or saved as local files.

## What it does

Given a test run ID, the skill:

1. Fetches all Perfana data (transactions, SLO checks, ADAPT regressions, errors, rankings)
2. Automatically finds a baseline run for comparison
3. Classifies regressions (computation, latency, GC, connection pool, errors, etc.)
4. Investigates root causes across connected data sources (Tempo traces, Pyroscope flamegraphs, Dynatrace problems, Grafana dashboards)
5. Correlates evidence across sources and assigns confidence levels
6. Generates a standardised Markdown report
7. Writes the report to Obsidian or saves it as a local Markdown file

## Prerequisites

### 1. Perfana MCP server

The skill requires the Perfana MCP server to be running and configured in Claude Code.

Add to your Claude Code MCP config (`~/.claude/claude_desktop_config.json` or project `.claude/settings.local.json`):

```json
{
  "mcpServers": {
    "perfana": {
      "command": "node",
      "args": ["apps/mcp/dist/index.js"],
      "env": {
        "PERFANA_BASE_URL": "http://localhost:3001/api",
        "PERFANA_API_KEY": "<your-perfana-api-key>"
      }
    }
  }
}
```

To get an API key, go to the Perfana UI (http://localhost:4001) > Settings > API Keys.

#### Auto-allow all Perfana MCP tools

By default, Claude Code will prompt you to approve each MCP tool call individually (~20 prompts per report). To allow all Perfana tools at once, add a wildcard permission to your project settings:

In `.claude/settings.local.json`:
```json
{
  "permissions": {
    "allow": [
      "mcp__perfana__*"
    ]
  }
}
```

This grants blanket permission to all `mcp__perfana__*` tools (get_test_run, get_adapt_results, get_transaction_stats, etc.) so the skill can run without interruption.

### 2. Obsidian with Local REST API plugin (optional)

Only needed if you want to write reports directly into an Obsidian vault. If you choose "local file" when running the skill, you can skip this entirely.

To set up Obsidian output:

1. Open Obsidian
2. Go to Settings > Community Plugins > Browse
3. Search for "Local REST API" and install it
4. Enable the plugin
5. In the plugin settings, enable "Enable Insecure Server" (for HTTP on port 27123)

The skill reads the API key automatically from:
```
{vaultRoot}/.obsidian/plugins/obsidian-local-rest-api/data.json
```

To auto-read the Obsidian API key, the skill uses the Filesystem MCP. If not available, you can pass the API key manually.

## Installation

The skill is already installed at `.claude/skills/perfana-report/` in this repository. Claude Code automatically discovers skills in the `.claude/skills/` directory.

To verify it's loaded, start Claude Code and check that `/perfana-report` appears in the skill list.

## Usage

Trigger the skill with natural language:

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

The skill also triggers on:
- "generate a Perfana report"
- "write a performance test report"
- "find root cause"
- "investigate regression"

## Report output

The skill asks whether to write to Obsidian or save as a local file:
- **Obsidian**: writes to `Performance Reports/{testRunId}.md` in your vault
- **Local file**: writes to `./reports/{testRunId}.md` in the current directory

Each report includes:

- **Summary** -- system, environment, workload, duration, overall result
- **Verdict** -- ADAPT regression analysis, SLO check results
- **Transaction performance** -- response times, Apdex scores, p99 tail overshoot, impact ranking
- **Regression analysis** -- classified regressions with hypotheses, config diff vs baseline
- **Error analysis** -- error rates by status code and transaction, flaky endpoint detection
- **Cross-source investigation** -- trace drill-downs, CPU profiling hotspots, Dynatrace problems, dashboard snapshots
- **Root cause & recommendations** -- evidence chain, confidence level, actionable next steps
- **Run trend** -- recent run history for the same SUT/environment/workload

## File structure

```
.claude/skills/perfana-report/
  SKILL.md                              # Skill definition (steps, error handling)
  README.md                             # This file
  references/
    classification-rules.md             # Regression classification table and hypothesis guide
    investigation-playbook.md           # Maps hypotheses to MCP tool calls
    report-template.md                  # Markdown report template
    obsidian-api.md                     # Obsidian Local REST API reference
```

## Customisation

- **Report template**: Edit `references/report-template.md` to change the report structure
- **Classification rules**: Edit `references/classification-rules.md` to add custom regression classifications
- **Investigation playbook**: Edit `references/investigation-playbook.md` to add new data source integrations
