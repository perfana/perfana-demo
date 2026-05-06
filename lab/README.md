# 18k rps DB Stress Lab

Lab harness that proves the praegus-gitops postgres + pgbouncer tuning, TimescaleDB CAGGs, and rollup tables hold under a 12-driver / 4-SUT / 18k rps ingest profile on an 8-core / 16GB envelope (emulated on Mac M1 Docker Desktop).

Spec: `docs/superpowers/specs/2026-05-06-db-stress-18k-rps-lab-design.md` (in the perfana repo).
Plan: `docs/superpowers/plans/2026-05-06-db-stress-18k-rps-lab-implementation.md` (in the perfana repo).

## Operator-supplied inputs (REQUIRED before first run)

1. **`lab/.env`** — copy from `.env.example` and adjust passwords if needed
2. **`lab/driver/url-patterns.txt`** — copy from `.example` and customise to match the URL shape your production traffic produces. One URL template per line; `:param` for placeholders; optional leading weight.

Optional knobs in `lab/.env`:
- `DRIVER_RPS` (default 1500)
- `DRIVER_DURATION` (default `PT1H`; use `PT5M` for smoke runs)
- `DRIVER_ERROR_RATE` (default 0.01)
- `DRIVER_SAVE_RESPONSE_BODY` (default true)
- `DRIVER_RESPONSE_BODY_SIZE_MIX` (default `500:80,5000:15,50000:5`)
- `DRIVER_ERROR_CODE_MIX` (default `500:30,502:15,503:15,504:15,408:15,429:10`)

## Prerequisites

- Docker Desktop on macOS (Apple Silicon) with **>= 24 GB allocated** to the VM (Settings -> Resources -> Memory)
- Java 17 (Gradle wrapper handles the rest)
- Python 3.11+ with `matplotlib` and `pandas` (`pip install -r lab/reports/requirements.txt`)
- `~/workspace/perfana-jmeter-timescaledb` cloned and published to mavenLocal:
  ```
  cd ~/workspace/perfana-jmeter-timescaledb && ./gradlew publishToMavenLocal
  ```
- Driver Docker image built:
  ```
  cd lab/driver && ./gradlew shadowJar
  docker build -t perfana/lab-driver:0.1.0 -f docker/Dockerfile .
  ```

## Running

```
cd ~/workspace/perfana-demo
git checkout lab/db-stress-18k-rps

# One-time setup (after cloning fresh)
cp lab/.env.example lab/.env
cp lab/driver/url-patterns.txt.example lab/driver/url-patterns.txt
# ... edit url-patterns.txt to match your production URL shape ...

# All three stages back-to-back (~3.5 hours)
./lab/scripts/run-soak.sh --stage all

# Or one stage at a time
./lab/scripts/run-soak.sh --stage 1
./lab/scripts/run-soak.sh --stage 2 --use-snapshot lab/snapshots/post-stage1-XXX.tgz
./lab/scripts/run-soak.sh --stage 3
```

## Output

Per-run reports land at `lab/reports/<RUN_TS>/<stage>/report.md` with:
- SLO pass/fail table
- Inline PNG plots (rps target vs actual, WAL bytes, pgbouncer pool, perf-analysis latency, CAGG runtime, postgres CPU)
- Links to raw CSVs

Stage 1 also writes `lab/snapshots/post-stage1-<RUN_TS>.tgz` for Stage 2 replay.

## SLO matrix

See spec section 7. Three groups:

- **I-* (ingest)**: rps fidelity, no driver buffer pressure, postgres mem stable, WAL bounded, pgbouncer no waits, CAGG no failures
- **Q-* (query)**: Performance Analysis card latency under bound (post-rollup vs live-aggregation paths)
- **W-* (worker)**: force re-fetch under bound

## Troubleshooting

- **Stage 1 fails I-1 (rps actual lags target)**: drivers are CPU-starved or DB is back-pressuring.
  - Check `lab/reports/*/stage1-ingest/timeseries/pgbouncer_pools.csv` for `cl_waiting > 0`.
  - Check `lab/reports/*/stage1-ingest/timeseries/docker_stats.csv` for postgres CPU at 100%.
- **Stage 2 fails Q-* (planner uses requests_raw)**: rollup table missing for one of the test runs.
  - Verify via psql: `SELECT count(*) FROM test_run_transaction_stats WHERE test_run_id IN (...);`
  - If empty, the worker rollup pipeline didn't auto-fire — fire manually with `trigger-refetch.sh`.
- **Driver image build fails**: ensure perfana-jmeter-timescaledb is in mavenLocal.
- **CAGG catch-up never completes**: check `timescaledb.max_background_workers = 16` in postgresql.conf.
- **Chunk distribution check fails (verify-chunk-distribution.sh)**: two SUTs hashed to the same partition — rename one (e.g., `lab-sut-a` -> `lab-sut-aa`) in `docker-compose.drivers.yml` and rerun.
