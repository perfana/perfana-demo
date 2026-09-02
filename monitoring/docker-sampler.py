#!/usr/bin/env python3
"""Sample per-container CPU, memory, block and network I/O into monitoring.pg_samples.

Prints INSERT statements on stdout; the wrapper pipes them into a single long-lived
psql, exactly like redis-sampler.py.

Reads the Docker API through docker-socket-proxy, so this container never sees the
socket itself and is limited to the GET /containers endpoints the proxy allows. Uses
urllib from the standard library, which keeps the sampler on the stock
timescale/timescaledb-ha image — no extra image, no package install, no internet.

Counters (CPU time, bytes, throttled time) are stored raw and differenced in the
dashboard with LAG(), the same convention as the PostgreSQL and Valkey samples.
"""
import json
import os
import sys
import time
import urllib.request

API = os.environ.get("DOCKER_API", "http://docker-socket-proxy:2375").rstrip("/")
INTERVAL = float(os.environ.get("SAMPLE_INTERVAL", "15"))
TIMEOUT = float(os.environ.get("DOCKER_TIMEOUT", "10"))


def api(path):
    with urllib.request.urlopen(f"{API}{path}", timeout=TIMEOUT) as r:
        return json.load(r)


def containers():
    """Running containers as (id, name). The leading slash on Names[0] is Docker's."""
    for c in api("/containers/json"):
        names = c.get("Names") or []
        yield c["Id"], (names[0].lstrip("/") if names else c["Id"][:12])


def stats_rows(name, s):
    """Yield (metric, source, value) for one container's stats blob."""
    cpu = s.get("cpu_stats") or {}
    usage = (cpu.get("cpu_usage") or {}).get("total_usage")
    if usage is not None:
        yield "docker.cpu.usage_ns", name, float(usage)
    # online_cpus is how many host cores the container may use — the ceiling the
    # "cores used" panel is read against. Absent on some platforms; percpu_usage is
    # the documented fallback.
    online = cpu.get("online_cpus") or len((cpu.get("cpu_usage") or {}).get("percpu_usage") or [])
    if online:
        yield "docker.cpu.online", name, float(online)

    thr = cpu.get("throttling_data") or {}
    for key, metric in (("periods", "docker.cpu.periods"),
                        ("throttled_periods", "docker.cpu.throttled_periods"),
                        ("throttled_time", "docker.cpu.throttled_ns")):
        if thr.get(key) is not None:
            yield metric, name, float(thr[key])

    mem = s.get("memory_stats") or {}
    detail = mem.get("stats") or {}
    if mem.get("usage") is not None:
        yield "docker.mem.usage_bytes", name, float(mem["usage"])
        # Working set is what actually has to stay resident: page cache that can be
        # evicted under pressure does not count. cgroup v2 calls it inactive_file,
        # v1 total_inactive_file — WSL2 is v2, but both hosts run this file.
        inactive = detail.get("inactive_file", detail.get("total_inactive_file", 0))
        yield "docker.mem.working_set_bytes", name, float(max(mem["usage"] - inactive, 0))
    if mem.get("limit"):
        yield "docker.mem.limit_bytes", name, float(mem["limit"])

    # Block I/O. Empty on some cgroup v2 setups, hence the guard rather than a KeyError.
    blk = (s.get("blkio_stats") or {}).get("io_service_bytes_recursive") or []
    for op, metric in (("read", "docker.blkio.read_bytes"), ("write", "docker.blkio.write_bytes")):
        total = sum(e.get("value", 0) for e in blk if str(e.get("op", "")).lower() == op)
        if blk:
            yield metric, name, float(total)

    nets = s.get("networks") or {}
    if nets:
        yield "docker.net.rx_bytes", name, float(sum(n.get("rx_bytes", 0) for n in nets.values()))
        yield "docker.net.tx_bytes", name, float(sum(n.get("tx_bytes", 0) for n in nets.values()))

    pids = s.get("pids_stats") or {}
    if pids.get("current") is not None:
        yield "docker.pids.current", name, float(pids["current"])


def rows():
    for cid, name in containers():
        try:
            # one-shot=true returns immediately. Without it the daemon holds the request
            # open for a second to fill precpu_stats, which would put a dozen containers
            # well past the sample interval — and the dashboard differences the raw
            # counters itself, so precpu is of no use here anyway.
            s = api(f"/containers/{cid}/stats?stream=false&one-shot=true")
        except Exception as exc:  # noqa: BLE001 — one dead container is not a failed sample
            print(f"-- stats failed for {name}: {exc}", file=sys.stderr, flush=True)
            continue
        yield from stats_rows(name, s)


def emit(batch):
    values = ",".join(
        "(now(), '%s', '%s', '', %r)" % (m, s.replace("'", "''"), v) for m, s, v in batch
    )
    print(
        "INSERT INTO monitoring.pg_samples (ts, metric, source, detail, value) "
        f"VALUES {values};",
        flush=True,
    )


def main():
    while True:
        started = time.monotonic()
        batch = None
        try:
            batch = list(rows())
        except Exception as exc:  # noqa: BLE001 — a sampler must outlive a daemon blip
            print(f"-- docker sample failed: {exc}", file=sys.stderr, flush=True)

        if batch:
            # A closed stdout means psql is gone — after a database restart, say. Exit and
            # let the restart policy bring the pair back up together, as redis-sampler does.
            try:
                emit(batch)
            except BrokenPipeError:
                print("psql closed the pipe — exiting so the container restarts",
                      file=sys.stderr, flush=True)
                os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
                return 1

        time.sleep(max(0.0, INTERVAL - (time.monotonic() - started)))


if __name__ == "__main__":
    sys.exit(main() or 0)
