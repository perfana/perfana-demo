#!/usr/bin/env python3
"""Sample Valkey/Redis and the BullMQ queues into monitoring.pg_samples.

Prints INSERT statements on stdout; the wrapper pipes them into a single long-lived
psql, so one connection serves every sample instead of reconnecting each round.

Speaks RESP over a plain socket. That keeps the sampler on the stock
timescale/timescaledb-ha image, which already carries python3 and psql, so this needs
no extra image, no package install and works on a host with no internet access.
"""
import os
import socket
import sys
import time

HOST = os.environ.get("REDIS_HOST", "redis")
PORT = int(os.environ.get("REDIS_PORT", "6379"))
INTERVAL = float(os.environ.get("SAMPLE_INTERVAL", "10"))
TIMEOUT = float(os.environ.get("REDIS_TIMEOUT", "5"))

# One EVAL returns every queue depth as a single bulk string, so the client parses one
# reply instead of walking a nested array. Queues are discovered from their :meta key
# rather than hardcoded — Perfana adds queues over time.
BULL_LUA = """
local out = {}
for _, k in ipairs(redis.call('KEYS', 'bull:*:meta')) do
  local q = string.match(k, '^bull:(.+):meta$')
  local p = 'bull:' .. q .. ':'
  out[#out+1] = q .. ' wait '      .. redis.call('LLEN',  p .. 'wait')
  out[#out+1] = q .. ' active '    .. redis.call('LLEN',  p .. 'active')
  out[#out+1] = q .. ' delayed '   .. redis.call('ZCARD', p .. 'delayed')
  out[#out+1] = q .. ' failed '    .. redis.call('ZCARD', p .. 'failed')
  out[#out+1] = q .. ' completed ' .. redis.call('ZCARD', p .. 'completed')
  out[#out+1] = q .. ' paused '    .. redis.call('LLEN',  p .. 'paused')
end
return table.concat(out, '\\n')
"""

# Gauges and counters worth keeping. Counters are stored raw and differenced in the
# dashboard, exactly like the PostgreSQL samples.
INFO_FIELDS = [
    "connected_clients", "blocked_clients", "used_memory", "used_memory_rss",
    "used_memory_peak", "maxmemory", "mem_fragmentation_ratio",
    "instantaneous_ops_per_sec", "total_commands_processed",
    "total_connections_received", "rejected_connections",
    "keyspace_hits", "keyspace_misses", "evicted_keys", "expired_keys",
    "total_net_input_bytes", "total_net_output_bytes",
    "rdb_changes_since_last_save", "latest_fork_usec", "uptime_in_seconds",
]


def encode(*args):
    """RESP array — safe for arguments containing newlines, unlike inline commands."""
    out = [f"*{len(args)}\r\n".encode()]
    for a in args:
        b = a.encode() if isinstance(a, str) else a
        out.append(b"$%d\r\n%s\r\n" % (len(b), b))
    return b"".join(out)


class Redis:
    def __init__(self):
        self.sock = socket.create_connection((HOST, PORT), timeout=TIMEOUT)
        self.buf = b""

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass

    def _line(self):
        while b"\r\n" not in self.buf:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("connection closed by server")
            self.buf += chunk
        line, self.buf = self.buf.split(b"\r\n", 1)
        return line

    def _read(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("connection closed by server")
            self.buf += chunk
        data, self.buf = self.buf[:n], self.buf[n:]
        return data

    def command(self, *args):
        self.sock.sendall(encode(*args))
        head = self._line()
        kind, rest = head[:1], head[1:]
        if kind == b"$":
            n = int(rest)
            if n == -1:
                return None
            data = self._read(n)
            self._read(2)  # trailing CRLF
            return data.decode("utf-8", "replace")
        if kind == b":":
            return int(rest)
        if kind == b"+":
            return rest.decode()
        if kind == b"-":
            raise RuntimeError(rest.decode())
        raise RuntimeError(f"unexpected reply type {head!r}")


def rows(r):
    """Yield (metric, source, value) for one sample."""
    info = r.command("INFO")
    fields = {}
    for line in info.splitlines():
        if ":" in line and not line.startswith("#"):
            k, _, v = line.partition(":")
            fields[k.strip()] = v.strip()

    for name in INFO_FIELDS:
        raw = fields.get(name)
        if raw is None:
            continue
        try:
            yield f"redis.{name}", "", float(raw)
        except ValueError:
            continue

    # Key count per logical database, from lines like "db0:keys=107,expires=7,avg_ttl=0".
    for k, v in fields.items():
        if k.startswith("db") and k[2:].isdigit() and "keys=" in v:
            count = v.split("keys=", 1)[1].split(",", 1)[0]
            yield "redis.keys", k, float(count)

    depths = r.command("EVAL", BULL_LUA, "0") or ""
    for line in depths.splitlines():
        parts = line.rsplit(" ", 2)
        if len(parts) == 3:
            queue, state, value = parts
            yield f"queue.{state}", queue, float(value)


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
    r = None
    while True:
        started = time.monotonic()
        try:
            if r is None:
                r = Redis()
            batch = list(rows(r))
            if batch:
                emit(batch)
        except Exception as exc:  # noqa: BLE001 — a sampler must outlive any single error
            print(f"-- redis sample failed: {exc}", file=sys.stderr, flush=True)
            if r is not None:
                r.close()
            r = None
        time.sleep(max(0.0, INTERVAL - (time.monotonic() - started)))


if __name__ == "__main__":
    main()
