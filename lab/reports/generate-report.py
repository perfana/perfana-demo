#!/usr/bin/env python3
"""Generates report.md + PNG plots from CSVs under <stage-dir>/."""
import argparse
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd


def load_csv(path: Path) -> pd.DataFrame:
    if not path.exists() or path.stat().st_size == 0:
        return pd.DataFrame()
    try:
        return pd.read_csv(path)
    except (pd.errors.EmptyDataError, pd.errors.ParserError):
        return pd.DataFrame()


def plot_save(df: pd.DataFrame, x: str, ys: list, title: str, ylabel: str, out: Path) -> bool:
    if df.empty:
        return False
    have = [y for y in ys if y in df.columns]
    if not have:
        return False
    fig, ax = plt.subplots(figsize=(10, 4))
    for y in have:
        try:
            ax.plot(pd.to_datetime(df[x]), df[y], label=y, linewidth=1.0)
        except Exception:
            continue
    ax.set_title(title)
    ax.set_xlabel("time")
    ax.set_ylabel(ylabel)
    ax.legend()
    ax.grid(alpha=0.3)
    fig.autofmt_xdate()
    fig.tight_layout()
    fig.savefig(out, dpi=100)
    plt.close(fig)
    return True


def stage_slos(stage: int) -> list:
    base = [
        ("I-4", "postgres memory stable, no OOM"),
        ("I-6", "pgbouncer cl_waiting = 0"),
        ("I-7", "CAGG refresh policies on schedule"),
    ]
    if stage == 1:
        return base + [
            ("I-1", "rps_actual >= 0.98 * rps_target per driver"),
            ("I-2", "no driver buffer pressure"),
            ("I-3", "no backpressure events outside url_patterns startup"),
            ("I-5", "WAL bytes <= max_wal_size = 8 GB"),
        ]
    if stage == 2:
        return base + [
            ("Q-1", "GET /transactions p95 < 1s, p99 < 3s (post-rollup)"),
            ("Q-2", "GET /throughput, /virtual-users p95 < 1s"),
            ("W-1", "force re-fetch < 5 min"),
        ]
    if stage == 3:
        return base + [
            ("I-1", "rps_actual >= 0.98 * rps_target per driver"),
            ("I-2", "no driver buffer pressure"),
            ("I-5", "WAL bytes bounded"),
            ("Q-3", "GET /transactions p95 < 5s (live-aggregation)"),
            ("Q-4", "GET /transactions p99 < 10s"),
            ("W-2", "force re-fetch < 15 min under load"),
        ]
    return base


def evaluate_slos(stage: int, dir: Path) -> list:
    """Returns [(slo_id, status, evidence), ...]."""
    rows = []
    drv = load_csv(dir / "driver_metrics.csv")
    pgb = load_csv(dir / "timeseries" / "pgbouncer_pools.csv")
    perf = load_csv(dir / "perf-analysis-latency.csv")
    refetch = load_csv(dir / "refetch-timing.csv")
    cagg = load_csv(dir / "timeseries" / "cagg_jobs.csv")

    for slo_id, _ in stage_slos(stage):
        status, evidence = "?", "no data"
        try:
            if slo_id == "I-1" and not drv.empty and "rps_actual" in drv.columns and "rps_target" in drv.columns:
                drv2 = drv[(drv["rps_target"] > 0) & (drv["rps_actual"] >= 0)]
                if not drv2.empty:
                    ratio = (drv2["rps_actual"].astype(float) / drv2["rps_target"].astype(float)).min()
                    status = "PASS" if ratio >= 0.98 else "FAIL"
                    evidence = f"min(rps_actual/rps_target) = {ratio:.3f}"
            elif slo_id == "I-2" and not drv.empty and "buffer_total" in drv.columns:
                mx = drv["buffer_total"].astype(int).max()
                status = "PASS" if mx < 50_000 else "WARN"
                evidence = f"max(buffer_total) = {mx}"
            elif slo_id == "I-3" and not drv.empty and "under_pressure" in drv.columns:
                bp = drv["under_pressure"].astype(int).max()
                status = "PASS" if bp == 0 else "WARN"
                evidence = f"max(under_pressure) = {bp}"
            elif slo_id == "I-6" and not pgb.empty:
                sub = pgb[pgb.get("database", "") == "perfana"]
                if not sub.empty and "cl_waiting" in sub.columns:
                    mx = sub["cl_waiting"].astype(int).max()
                    status = "PASS" if mx == 0 else "FAIL"
                    evidence = f"max(cl_waiting on perfana db) = {mx}"
            elif slo_id == "I-7" and not cagg.empty and "total_failures" in cagg.columns:
                failures = cagg["total_failures"].astype(int).max()
                status = "PASS" if failures == 0 else "FAIL"
                evidence = f"max(total_failures across CAGGs) = {failures}"
            elif slo_id in ("Q-1", "Q-3") and not perf.empty:
                mask = perf["endpoint"].str.endswith("/transactions")
                sub = perf[mask & (perf["http_status"].astype(int) == 200)]
                if not sub.empty:
                    p95 = sub["latency_ms"].astype(float).quantile(0.95)
                    bound = 1000 if slo_id == "Q-1" else 5000
                    status = "PASS" if p95 < bound else "FAIL"
                    evidence = f"p95 = {p95:.0f} ms (bound {bound} ms)"
            elif slo_id == "Q-4" and not perf.empty:
                mask = perf["endpoint"].str.endswith("/transactions")
                sub = perf[mask & (perf["http_status"].astype(int) == 200)]
                if not sub.empty:
                    p99 = sub["latency_ms"].astype(float).quantile(0.99)
                    status = "PASS" if p99 < 10000 else "FAIL"
                    evidence = f"p99 = {p99:.0f} ms (bound 10000 ms)"
            elif slo_id in ("W-1", "W-2") and not refetch.empty and "total_ms" in refetch.columns:
                mx = refetch["total_ms"].astype(int).max()
                bound = 5 * 60_000 if slo_id == "W-1" else 15 * 60_000
                status = "PASS" if mx < bound else "FAIL"
                evidence = f"max(total_ms) = {mx} (bound {bound})"
        except Exception as e:
            status = "?"
            evidence = f"eval error: {e}"
        rows.append((slo_id, status, evidence))
    return rows


def write_report(stage: int, dir: Path) -> None:
    plots = []
    drv = load_csv(dir / "driver_metrics.csv")
    pgw = load_csv(dir / "timeseries" / "pg_wal_bgwriter.csv")
    pgb = load_csv(dir / "timeseries" / "pgbouncer_pools.csv")
    rel = load_csv(dir / "timeseries" / "relation_sizes.csv")
    perf = load_csv(dir / "perf-analysis-latency.csv")
    cagg = load_csv(dir / "timeseries" / "cagg_jobs.csv")
    docker = load_csv(dir / "timeseries" / "docker_stats.csv")

    if not drv.empty and "rps_target" in drv.columns:
        for sut, sub in drv.groupby("sut"):
            if plot_save(sub, "timestamp", ["rps_target", "rps_actual"],
                         f"rps target vs actual — {sut}", "rps", dir / f"plot_rps_{sut}.png"):
                plots.append(f"plot_rps_{sut}.png")

    if not pgw.empty and plot_save(pgw, "timestamp", ["wal_bytes"], "WAL bytes accumulated", "bytes",
                                    dir / "plot_wal.png"):
        plots.append("plot_wal.png")

    if not pgb.empty:
        sub = pgb[pgb.get("database", "") == "perfana"]
        if plot_save(sub, "timestamp", ["cl_active", "cl_waiting", "sv_active"],
                     "pgbouncer pool activity (perfana DB)", "connections",
                     dir / "plot_pgbouncer.png"):
            plots.append("plot_pgbouncer.png")

    if not perf.empty:
        sub = perf[perf["http_status"].astype(int) == 200].copy()
        sub["timestamp"] = pd.to_datetime(sub["timestamp"])
        if plot_save(sub, "timestamp", ["latency_ms"], "perf-analysis API latency (200 OK)", "ms",
                     dir / "plot_perf_latency.png"):
            plots.append("plot_perf_latency.png")

    if not rel.empty:
        sub = rel[rel["table"] == "requests_raw"]
        if plot_save(sub, "timestamp", ["total_bytes"], "requests_raw size growth", "bytes",
                     dir / "plot_requests_raw_size.png"):
            plots.append("plot_requests_raw_size.png")

    if not cagg.empty and "last_run_runtime_ms" in cagg.columns:
        if plot_save(cagg, "timestamp", ["last_run_runtime_ms"], "CAGG refresh runtime", "ms",
                     dir / "plot_cagg_runtime.png"):
            plots.append("plot_cagg_runtime.png")

    if not docker.empty:
        sub = docker[docker["container"].str.contains("perfana-lab-postgres", na=False)].copy()
        if not sub.empty and "cpu_percent" in sub.columns:
            try:
                sub["cpu"] = sub["cpu_percent"].astype(str).str.rstrip("%").astype(float)
                if plot_save(sub, "timestamp", ["cpu"], "postgres container CPU %", "%",
                             dir / "plot_pg_cpu.png"):
                    plots.append("plot_pg_cpu.png")
            except Exception:
                pass

    slos = evaluate_slos(stage, dir)

    md = dir / "report.md"
    with md.open("w") as f:
        f.write(f"# Stage {stage} — Soak Report\n\n")
        f.write(f"Run directory: `{dir}`\n\n")
        f.write("## SLO results\n\n| ID | Status | Evidence | Description |\n|---|---|---|---|\n")
        slo_descs = dict(stage_slos(stage))
        badges = {"PASS": "PASS", "FAIL": "FAIL", "WARN": "WARN", "?": "?"}
        for slo_id, status, evidence in slos:
            f.write(f"| {slo_id} | {badges[status]} | {evidence} | {slo_descs.get(slo_id, '')} |\n")
        f.write("\n## Plots\n\n")
        for p in plots:
            f.write(f"![{p}]({p})\n\n")
        f.write("\n## Raw data\n\n")
        for csv in sorted(dir.rglob("*.csv")):
            rel_path = csv.relative_to(dir)
            f.write(f"- [{rel_path}]({rel_path})\n")

    print(f"wrote {md}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--stage", type=int, required=True)
    p.add_argument("--dir", type=Path, required=True)
    args = p.parse_args()
    write_report(args.stage, args.dir)


if __name__ == "__main__":
    main()
