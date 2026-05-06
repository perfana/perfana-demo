#!/usr/bin/env bash
# 10s polling loop emitting CSVs into $1 (run/stage dir).
# Stops gracefully on SIGTERM (run-soak.sh sends SIGTERM at stage end).
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

OUT_DIR="${1:?usage: $0 <out-dir>}"
mkdir -p "$OUT_DIR/timeseries"

log_info "Observability starting -> $OUT_DIR/timeseries"

# CSV headers
echo "timestamp,xact_commit,blks_read,blks_hit,tup_inserted,tup_updated,deadlocks,conflicts" \
  > "$OUT_DIR/timeseries/pg_stat_database.csv"
echo "timestamp,buffers_clean,buffers_backend,wal_bytes,wal_write_time" \
  > "$OUT_DIR/timeseries/pg_wal_bgwriter.csv"
echo "timestamp,active,idle,idle_in_tx,oldest_active_query_seconds" \
  > "$OUT_DIR/timeseries/pg_activity.csv"
echo "timestamp,table,total_bytes,toast_bytes" \
  > "$OUT_DIR/timeseries/relation_sizes.csv"
echo "timestamp,hypertable,chunks,total_bytes" \
  > "$OUT_DIR/timeseries/ts_chunks.csv"
echo "timestamp,view,last_run_started,last_run_runtime_ms,last_status,total_runs,total_failures" \
  > "$OUT_DIR/timeseries/cagg_jobs.csv"
echo "timestamp,database,user,cl_active,cl_waiting,sv_active,sv_idle,sv_used,sv_tested,sv_login,maxwait" \
  > "$OUT_DIR/timeseries/pgbouncer_pools.csv"
echo "timestamp,container,cpu_percent,mem_usage,mem_pct,net_io,block_io" \
  > "$OUT_DIR/timeseries/docker_stats.csv"

trap 'log_info "Observability stopping"; exit 0' TERM INT

while true; do
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # pg_stat_database
  psql_run_quiet -c "
    SELECT '$TS,' || xact_commit || ',' || blks_read || ',' || blks_hit || ','
      || tup_inserted || ',' || tup_updated || ',' || deadlocks || ',' || conflicts
    FROM pg_stat_database WHERE datname='perfana';" \
    >> "$OUT_DIR/timeseries/pg_stat_database.csv" 2>/dev/null || true

  # pg_stat_bgwriter + pg_stat_wal (pg16)
  psql_run_quiet -c "
    SELECT '$TS,' || coalesce(b.buffers_clean,0) || ',' || coalesce(b.buffers_backend,0) || ','
      || coalesce(w.wal_bytes,0) || ',' || coalesce(w.wal_write_time,0)
    FROM pg_stat_bgwriter b CROSS JOIN pg_stat_wal w;" \
    >> "$OUT_DIR/timeseries/pg_wal_bgwriter.csv" 2>/dev/null || true

  # pg_stat_activity counts + oldest active query age
  psql_run_quiet -c "
    SELECT '$TS,'
      || count(*) FILTER (WHERE state='active') || ','
      || count(*) FILTER (WHERE state='idle') || ','
      || count(*) FILTER (WHERE state='idle in transaction') || ','
      || coalesce(EXTRACT(epoch FROM max(now() - query_start)) FILTER (WHERE state='active'), 0)
    FROM pg_stat_activity WHERE datname='perfana';" \
    >> "$OUT_DIR/timeseries/pg_activity.csv" 2>/dev/null || true

  # Relation sizes for hot tables + their TOAST
  for tbl in requests_raw requests_error transactions virtual_users url_patterns; do
    psql_run_quiet -c "
      SELECT '$TS,$tbl,' || pg_total_relation_size('$tbl') || ','
        || coalesce(pg_relation_size((SELECT reltoastrelid FROM pg_class WHERE relname='$tbl' LIMIT 1)), 0);" \
      >> "$OUT_DIR/timeseries/relation_sizes.csv" 2>/dev/null || true
  done

  # TimescaleDB chunks per hypertable
  psql_run_quiet -c "
    SELECT '$TS,' || hypertable_name || ',' || count(*) || ',' || coalesce(sum(c.range_end - c.range_start), 0)
    FROM timescaledb_information.chunks
    LEFT JOIN LATERAL (SELECT 0::bigint AS range_end, 0::bigint AS range_start) c ON true
    WHERE hypertable_name IN ('requests_raw','requests_error','transactions')
    GROUP BY 1;" \
    >> "$OUT_DIR/timeseries/ts_chunks.csv" 2>/dev/null || true

  # CAGG jobs
  psql_run_quiet -c "
    SELECT '$TS,' || coalesce((c.config->>'mat_hypertable_id')::text, j.application_name) || ','
      || coalesce(js.last_run_started_at::text,'') || ','
      || coalesce(EXTRACT(epoch FROM js.last_run_duration)*1000,0) || ','
      || coalesce(js.last_run_status,'') || ',' || js.total_runs || ',' || js.total_failures
    FROM timescaledb_information.job_stats js
    JOIN timescaledb_information.jobs j ON j.job_id = js.job_id
    LEFT JOIN LATERAL (SELECT '{}'::jsonb AS config) c ON true
    WHERE j.proc_name = 'policy_refresh_continuous_aggregate';" \
    >> "$OUT_DIR/timeseries/cagg_jobs.csv" 2>/dev/null || true

  # pgbouncer pools (one row per database/user)
  bouncer_admin "SHOW POOLS;" 2>/dev/null | while IFS='|' read -r db user cl_active cl_waiting sv_active sv_idle sv_used sv_tested sv_login maxwait rest; do
    [ -z "$db" ] && continue
    [ "$db" = "database" ] && continue
    echo "$TS,$db,$user,$cl_active,$cl_waiting,$sv_active,$sv_idle,$sv_used,$sv_tested,$sv_login,$maxwait" \
      >> "$OUT_DIR/timeseries/pgbouncer_pools.csv"
  done || true

  # docker stats (one snapshot per container)
  docker stats --no-stream --format "$TS,{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}},{{.NetIO}},{{.BlockIO}}" 2>/dev/null \
    | grep -E "perfana-lab-" \
    >> "$OUT_DIR/timeseries/docker_stats.csv" 2>/dev/null || true

  sleep 10
done
