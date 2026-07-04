# Perfana Demo

## Overview

The Perfana demo environment lets you explore all Perfana features using Docker Compose. It provides a realistic performance testing environment including load testing, metrics, distributed tracing, continuous profiling, and automated regression detection.

## Prerequisites

* [Docker](https://docs.docker.com/get-started/) with Docker Compose
* Minimum **8 GB RAM** allocated to Docker (16 GB recommended)
* `jq` installed (for the init script)

## Getting Started

Clone the repository:

```sh
git clone https://github.com/perfana/perfana-demo.git
cd perfana-demo
```

Run the initialization script (first time only):

```sh
./init-demo.sh
```

This starts all services, runs database migrations, configures integrations (Grafana, Tempo, Pyroscope), creates API keys, and runs an initial set of baseline load tests. It also configures ADAPT mode automatically — see [Detecting Regressions](#detecting-regressions) below.

### Dynatrace Mock (optional)

To also start WireMock-based Dynatrace API stubs (SaaS and Managed flavours), pass the `--dynatrace-mock` flag:

```sh
./init-demo.sh --dynatrace-mock
```

This starts two additional containers and automatically registers the Dynatrace instance and entity mappings (HOST + SERVICE) in Perfana.

## Services

| Container               | Description                              | Local port |
|:------------------------|:-----------------------------------------|:-----------|
| perfana-web             | Perfana UI (Next.js)                     | 4000       |
| perfana-api             | Perfana API (NestJS)                     | 3001       |
| perfana-worker          | Background job processor (BullMQ)        | —          |
| perfana-grafana-sync    | Grafana dashboard sync service           | —          |
| perfana-report          | PDF report generation                    | —          |
| keycloak                | Authentication server                    | 8080       |
| postgres                | TimescaleDB — Perfana data store         | 5432       |
| redis                   | Job queue                                | 6379       |
| pgbouncer               | PostgreSQL connection pooler (optional)  | 6432       |
| grafana                 | Grafana dashboards                       | 3000       |
| prometheus              | Metrics collection                       | 9090       |
| alertmanager            | Alert routing                            | 9093       |
| influxdb                | Time-series metrics (JMeter results)     | 8086       |
| tempo                   | Distributed tracing backend              | 3200       |
| pyroscope               | Continuous profiling                     | 4040       |
| loki                    | Log aggregation                          | 3100       |
| telegraf                | Docker metrics collector                 | —          |
| afterburner-fe          | Spring Boot test application (frontend)  | 8090       |
| afterburner-be          | Spring Boot test application (backend)   | —          |
| mariadb                 | Database used by afterburner             | 3306       |
| wiremock                | HTTP mock server                         | 8060       |
| dynatrace-mock          | Dynatrace SaaS API stub (optional)       | 8061       |
| dynatrace-managed-mock  | Dynatrace Managed API stub (optional)    | 8062       |

## Day-to-day Commands

```sh
# Start all existing containers (after init)
./start.sh

# Start infrastructure only (for local Perfana development)
./start-infra.sh

# Stop all containers
./stop.sh

# Remove all containers and volumes (data will be lost)
./clean.sh
```

## Running Load Tests

```sh
# Baseline test (establishes performance benchmarks)
./deploy-and-test-jmeter.sh baseline

# Test with CPU performance issue
./deploy-and-test-jmeter.sh cpu

# Test with connection pool issue
./deploy-and-test-jmeter.sh pool

# Test with slow backend calls issue
./deploy-and-test-jmeter.sh backend
```

Run a baseline first, then disable baseline mode in Perfana and run one of the issue variants to trigger automatic regression detection.

### Connection pooling with PgBouncer (optional)

PgBouncer is included but **disabled by default** — the single-node demo connects
to PostgreSQL directly and does not need it. Enable it only when you run a **large
number of distributed JMeter load generators**: each generator's TimescaleDB backend
listener opens its own pool of connections to PostgreSQL, and with many generators
this can exhaust PostgreSQL's `max_connections`. PgBouncer multiplexes those
connections in `transaction` pooling mode so a large fleet of generators maps onto a
small, bounded set of server connections.

Start it on demand (it listens on port `6432`):

```sh
docker compose --profile pgbouncer up -d pgbouncer
```

Then point the JMeter TimescaleDB backend listener at PgBouncer instead of
PostgreSQL by overriding the listener's host/port properties. In the `.jmx` test
plans these are JMeter properties that default to `postgres:5432`:

```sh
# Per-run override (host = pgbouncer, port = 6432)
jmeter -JtimescaleHost=pgbouncer -JtimescalePort=6432 ...

# From distributed generators outside the Docker network, use the host's
# address instead, e.g. -JtimescaleHost=<docker-host> -JtimescalePort=6432
```

> Config lives in `pgbouncer/pgbouncer.ini` (pool sizing) and `pgbouncer/userlist.txt`
> (auth). `userlist.txt` holds the `perfana` credentials; if you change
> `POSTGRES_PASSWORD`, update the password in that file to match.

## Detecting Regressions

ADAPT is Perfana's automated regression detection engine. It operates in two modes:

| Mode | Behaviour |
|:-----|:----------|
| **BASELINE** | Runs are auto-accepted into the control group. Use this to build up the reference dataset. |
| **DEFAULT** | Each run is compared against the last 10 successful baseline runs. Regressions are flagged automatically. |

### Automatic setup via `init-demo.sh`

`init-demo.sh` handles ADAPT mode switching automatically:

1. **Runs 1 & 2** — executed with ADAPT in **BASELINE** mode. Both runs are accepted into the control group and serve as the regression reference.
2. **Run 3** — before launching the issue test (`cpu`), ADAPT is switched to **DEFAULT** mode. Perfana immediately detects the regression and raises an alert.

### Manual steps (if running tests individually)

1. Run `./deploy-and-test-jmeter.sh baseline` twice to build the control group
2. In Perfana, go to **System Under Test → Config → ADAPT Settings** and switch the mode to **Default (regression)**
3. Run `./deploy-and-test-jmeter.sh cpu` (or `pool` / `backend`)
4. Perfana automatically compares against the baseline and flags regressions

## Analysing Results with Claude Code

The demo ships an MCP integration and a Claude Code skill that let you analyse test
runs and generate root-cause reports in natural language. The MCP server exposes
Perfana data to any MCP-compatible client (Claude Code, Claude Desktop); the
`perfana-report` skill orchestrates a full investigation on top of it.

### Perfana MCP

The [`@perfana/mcp`](https://www.npmjs.com/package/@perfana/mcp) server exposes test-run
data — transaction stats, SLO checks, ADAPT regressions, errors, traces (Tempo),
flamegraphs (Pyroscope) and Dynatrace problems — as MCP tools (`get_test_run`,
`get_adapt_results`, `get_slow_traces`, `list_connected_sources`, …). Once configured,
just ask Claude in plain English about any run.

**Setup.** `init-demo.sh` creates a dedicated API key (label `perfana-mcp`) and, when it
finishes, prints both an MCP config snippet and a one-line `claude mcp add` command.
The repo already ships a `.mcp.json` with the `perfana` and `grafana` servers wired up,
using a `PERFANA_API_KEY_PLACEHOLDER`. To activate it, either:

```sh
# Option A — paste the key from init-demo.sh output into .mcp.json,
#            replacing PERFANA_API_KEY_PLACEHOLDER

# Option B — let Claude Code register it for you (key from init-demo.sh output)
claude mcp add perfana \
  -e PERFANA_API_URL=http://localhost:3001/api \
  -e PERFANA_API_KEY=<your-perfana-mcp-key> \
  -- npx -y @perfana/mcp
```

> No API key? Generate one in the Perfana UI under **Settings → API Keys**.

Restart Claude Code after editing config. The tools then appear as `mcp__perfana__*`.
To skip the per-call approval prompts, allow them in bulk by adding
`"mcp__perfana__*"` to `permissions.allow` in `.claude/settings.local.json`.

The shipped `.mcp.json` also configures the **Grafana MCP** (`uvx mcp-grafana`, requires
[`uv`](https://docs.astral.sh/uv/)), which unlocks direct Pyroscope profiles, Loki log
queries and Tempo TraceQL during investigations. `init-demo.sh` prints its setup snippet too.

**Example prompts:**

```text
Compare the last 3 runs for PerfanaWebshop in test-env and tell me if anything regressed.
What was the Apdex for /checkout in run <testRunId>?
Are there CPU hotspots in the afterburner service during run <testRunId>?
```

### `perfana-report` skill

`perfana-report` (in `.claude/skills/perfana-report/`) turns a test run into a full,
standardised performance report. Given a run ID it fetches all Perfana data, finds a
baseline, classifies regressions, investigates root causes across the connected sources
(traces, logs, flamegraphs, infrastructure, Dynatrace), correlates the evidence with
confidence levels, and writes an opinionated Markdown report.

**Prerequisites**

* **Perfana MCP** — required (see above).
* **Grafana MCP** — recommended; deepens root-cause analysis with Pyroscope, Loki and Tempo.
* **Obsidian Local REST API** — optional; needed only to write the report straight into an
  Obsidian vault. Without it the report is saved to `./reports/{testRunId}.md`.

**Run it** from a Claude Code session in this repo by invoking the skill explicitly:

```text
/perfana-report

# or describe the task — e.g.
analyse test run PerfanaWebshop-acc-loadTest-00003 and write a report
```

The skill asks for a run ID (and optional baseline) and whether to write to Obsidian or a
local file, then runs the investigation end-to-end. See
`.claude/skills/perfana-report/README.md` for full details.

## Exploring the Environment

### Perfana

URL: [http://localhost:4000](http://localhost:4000)

| User | Password | Role |
|:-----|:---------|:-----|
| admin@perfana.io | Test@1234 | Admin |

### Grafana

URL: [http://localhost:3000](http://localhost:3000) — user: `perfana`, password: `perfana`

### Keycloak

URL: [http://localhost:8080](http://localhost:8080) — user: `admin`, password: `admin`

## Keeping Up to Date

```sh
git pull && docker compose pull
```

## Credits

JMeter load tests run on [BreakTest](https://github.com/Breaking-IT/breaktest), a JMeter-compatible fork.

The employee database used in this demo is derived from [datacharmer/test_db](https://github.com/datacharmer/test_db).
