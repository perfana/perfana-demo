-- =====================================================================================
-- Self-hosted PostgreSQL monitoring for the Perfana database.
--
-- Samples the pg_stat_* catalogs into a hypertable using TimescaleDB background jobs,
-- so the Grafana instance already provisioned against this database can graph database
-- health over time without an exporter, a Prometheus, or any extra container.
--
-- Everything lives in the "monitoring" schema and touches nothing Perfana owns.
-- Idempotent: safe to re-run. Apply with scripts/setup-db-monitoring.sh.
-- =====================================================================================

CREATE SCHEMA IF NOT EXISTS monitoring;

-- Long format on purpose: one table serves every metric, and adding a metric later is
-- one more INSERT in the sampler rather than a schema migration.
--   metric  what is measured, dotted namespace (conn.state, wal.bytes, job.failures)
--   source  first dimension: application_name, table name, job name, ...
--   detail  second dimension where one is not enough: connection state, lock mode
CREATE TABLE IF NOT EXISTS monitoring.pg_samples (
    ts     timestamptz      NOT NULL,
    metric text             NOT NULL,
    source text             NOT NULL DEFAULT '',
    detail text             NOT NULL DEFAULT '',
    value  double precision NOT NULL
);

SELECT create_hypertable('monitoring.pg_samples', 'ts',
                         chunk_time_interval => INTERVAL '1 hour',
                         if_not_exists => TRUE);

CREATE INDEX IF NOT EXISTS idx_pg_samples_metric
    ON monitoring.pg_samples (metric, ts DESC);

COMMENT ON TABLE monitoring.pg_samples IS
    'pg_stat_* samples written by monitoring.sample_fast/sample_slow. Counters are stored
     raw; turn them into rates in the dashboard with LAG() over (metric, source, detail).';

-- -------------------------------------------------------------------------------------
-- Fast sampler: things that move second to second.
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE monitoring.sample_fast(job_id int DEFAULT NULL, config jsonb DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    now_ts timestamptz := now();
BEGIN
    -- Connections per application and state. The write-starvation post-mortem in the
    -- Perfana repo (2026-03-26) split the worker into a 30-connection analytics pool and
    -- an 8-connection write pool precisely because analytics could starve writes, so
    -- saturation per application is the metric that matters most here. Requires the
    -- services to set PGAPPNAME; connections without it land under '(unset)'.
    INSERT INTO monitoring.pg_samples (ts, metric, source, detail, value)
    SELECT now_ts, 'conn.state',
           COALESCE(NULLIF(application_name, ''), '(unset)'),
           COALESCE(state, 'unknown'),
           count(*)
    FROM pg_stat_activity
    WHERE datname = current_database()
    GROUP BY 3, 4;

    -- Oldest transaction and query per application. idle-in-transaction holds back
    -- vacuum and pins a connection; ADAPT analysis legitimately runs for minutes, so
    -- read this next to conn.state rather than alerting on it blindly.
    INSERT INTO monitoring.pg_samples (ts, metric, source, detail, value)
    SELECT now_ts, m.metric,
           COALESCE(NULLIF(a.application_name, ''), '(unset)'), '',
           max(EXTRACT(EPOCH FROM (now_ts - m.since)))
    FROM pg_stat_activity a
    CROSS JOIN LATERAL (VALUES
        ('conn.xact_age_s', a.xact_start),
        ('conn.query_age_s', CASE WHEN a.state = 'active' THEN a.query_start END),
        ('conn.idle_in_xact_age_s', CASE WHEN a.state = 'idle in transaction' THEN a.state_change END)
    ) AS m(metric, since)
    WHERE a.datname = current_database() AND m.since IS NOT NULL
    GROUP BY 2, 3;

    -- Sessions blocked on a lock, and by which lock mode.
    INSERT INTO monitoring.pg_samples (ts, metric, source, detail, value)
    SELECT now_ts, 'lock.waiting', COALESCE(mode, 'unknown'), '', count(*)
    FROM pg_locks
    WHERE NOT granted
    GROUP BY 3;

    -- Connection budget. max_connections is 500 in this deployment; PgBouncer keeps a
    -- fleet of load generators from eating into it.
    INSERT INTO monitoring.pg_samples (ts, metric, source, detail, value)
    SELECT now_ts, 'conn.total', '', '', count(*) FROM pg_stat_activity
    UNION ALL
    SELECT now_ts, 'conn.max', '', '', current_setting('max_connections')::float;

    -- Database-wide counters. Stored raw; the dashboard differences them.
    INSERT INTO monitoring.pg_samples (ts, metric, source, detail, value)
    SELECT now_ts, 'db.' || m.metric, '', '', m.value
    FROM pg_stat_database d
    CROSS JOIN LATERAL (VALUES
        ('xact_commit', d.xact_commit::float),
        ('xact_rollback', d.xact_rollback::float),
        ('blks_read', d.blks_read::float),
        ('blks_hit', d.blks_hit::float),
        ('tup_returned', d.tup_returned::float),
        ('tup_fetched', d.tup_fetched::float),
        ('tup_inserted', d.tup_inserted::float),
        ('tup_updated', d.tup_updated::float),
        ('tup_deleted', d.tup_deleted::float),
        ('deadlocks', d.deadlocks::float),
        ('temp_files', d.temp_files::float),
        ('temp_bytes', d.temp_bytes::float),
        ('blk_read_time', d.blk_read_time),
        ('blk_write_time', d.blk_write_time),
        ('session_time', d.session_time),
        ('active_time', d.active_time),
        ('idle_in_transaction_time', d.idle_in_transaction_time),
        ('sessions', d.sessions::float),
        ('numbackends', d.numbackends::float)
    ) AS m(metric, value)
    WHERE d.datname = current_database();

    -- WAL. The JMeter TimescaleDB listener inserts in batches from every load generator,
    -- so WAL generation is the clearest signal of how hard a test is hitting the database.
    INSERT INTO monitoring.pg_samples (ts, metric, source, detail, value)
    SELECT now_ts, 'wal.lsn_bytes', '', '',
           (pg_current_wal_lsn() - '0/0'::pg_lsn)::float
    UNION ALL
    SELECT now_ts, 'wal.dir_bytes', '', '', COALESCE(sum(size), 0)::float FROM pg_ls_waldir()
    UNION ALL
    SELECT now_ts, 'wal.dir_files', '', '', count(*)::float FROM pg_ls_waldir();

    INSERT INTO monitoring.pg_samples (ts, metric, source, detail, value)
    SELECT now_ts, 'wal.' || m.metric, '', '', m.value
    FROM pg_stat_wal w
    CROSS JOIN LATERAL (VALUES
        ('records', w.wal_records::float),
        ('fpi', w.wal_fpi::float),
        ('bytes', w.wal_bytes::float),
        ('buffers_full', w.wal_buffers_full::float),
        ('write', w.wal_write::float),
        ('sync', w.wal_sync::float),
        ('write_time', w.wal_write_time),
        ('sync_time', w.wal_sync_time)
    ) AS m(metric, value);

    -- Checkpointer and background writer. buffers_backend rising against
    -- buffers_checkpoint means backends are flushing their own pages, and a high
    -- checkpoints_req share means checkpoints are driven by WAL volume, not by time.
    INSERT INTO monitoring.pg_samples (ts, metric, source, detail, value)
    SELECT now_ts, 'bgw.' || m.metric, '', '', m.value
    FROM pg_stat_bgwriter b
    CROSS JOIN LATERAL (VALUES
        ('checkpoints_timed', b.checkpoints_timed::float),
        ('checkpoints_req', b.checkpoints_req::float),
        ('checkpoint_write_time', b.checkpoint_write_time),
        ('checkpoint_sync_time', b.checkpoint_sync_time),
        ('buffers_checkpoint', b.buffers_checkpoint::float),
        ('buffers_clean', b.buffers_clean::float),
        ('maxwritten_clean', b.maxwritten_clean::float),
        ('buffers_backend', b.buffers_backend::float),
        ('buffers_backend_fsync', b.buffers_backend_fsync::float),
        ('buffers_alloc', b.buffers_alloc::float)
    ) AS m(metric, value);
END;
$$;

-- -------------------------------------------------------------------------------------
-- Slow sampler: things that move over minutes. Sizes and catalog scans are too
-- expensive to run every ten seconds and change far too slowly to need it.
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE monitoring.sample_slow(job_id int DEFAULT NULL, config jsonb DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    now_ts timestamptz := now();
BEGIN
    INSERT INTO monitoring.pg_samples (ts, metric, source, detail, value)
    SELECT now_ts, 'db.size_bytes', '', '', pg_database_size(current_database())::float;

    -- Hypertable sizes, uncompressed and compressed. The result tables grow with every
    -- test run; this is what fills the disk on a long-lived deployment.
    INSERT INTO monitoring.pg_samples (ts, metric, source, detail, value)
    SELECT now_ts, 'hypertable.bytes', h.hypertable_name, 'total',
           COALESCE(s.total_bytes, 0)::float
    FROM timescaledb_information.hypertables h
    CROSS JOIN LATERAL hypertable_detailed_size(
        format('%I.%I', h.hypertable_schema, h.hypertable_name)::regclass) s
    WHERE h.hypertable_schema NOT IN ('_timescaledb_internal', 'monitoring');

    -- Dead tuples per table. The result tables are insert-only, so anything but a low
    -- number here means autovacuum is falling behind.
    INSERT INTO monitoring.pg_samples (ts, metric, source, detail, value)
    SELECT now_ts, m.metric, t.relname, '', m.value
    FROM pg_stat_user_tables t
    CROSS JOIN LATERAL (VALUES
        ('table.dead_tup', t.n_dead_tup::float),
        ('table.live_tup', t.n_live_tup::float),
        ('table.autovacuum_age_s',
            EXTRACT(EPOCH FROM (now_ts - COALESCE(t.last_autovacuum, t.last_vacuum))))
    ) AS m(metric, value)
    WHERE t.schemaname = 'public' AND m.value IS NOT NULL AND t.n_live_tup > 0;

    -- TimescaleDB background jobs: the continuous aggregate refreshes that every Perfana
    -- dashboard reads from, plus the retention and columnstore policies. A refresh that
    -- stops succeeding shows up as stale dashboards long before it shows up as an error.
    INSERT INTO monitoring.pg_samples (ts, metric, source, detail, value)
    SELECT now_ts, m.metric, COALESCE(j.application_name, 'job ' || s.job_id), '', m.value
    FROM timescaledb_information.job_stats s
    JOIN timescaledb_information.jobs j USING (job_id)
    CROSS JOIN LATERAL (VALUES
        ('job.total_runs', s.total_runs::float),
        ('job.total_successes', s.total_successes::float),
        ('job.total_failures', s.total_failures::float),
        ('job.last_duration_s', EXTRACT(EPOCH FROM s.last_run_duration)),
        ('job.last_failed', CASE WHEN s.last_run_status = 'Failed' THEN 1 ELSE 0 END),
        -- TimescaleDB stores -infinity for a job that has never succeeded, and
        -- subtracting an infinite timestamp errors out rather than yielding NULL.
        ('job.age_since_success_s',
            CASE WHEN isfinite(s.last_successful_finish)
                 THEN EXTRACT(EPOCH FROM (now_ts - s.last_successful_finish)) END)
    ) AS m(metric, value)
    WHERE m.value IS NOT NULL;

    -- Worker budget. TimescaleDB background workers come out of max_worker_processes; if
    -- that is smaller than timescaledb.max_background_workers, jobs silently fail to
    -- start a worker when several policies fire at once.
    INSERT INTO monitoring.pg_samples (ts, metric, source, detail, value)
    SELECT now_ts, 'worker.max_worker_processes', '', '',
           current_setting('max_worker_processes')::float
    UNION ALL
    SELECT now_ts, 'worker.timescaledb_max_background', '', '',
           current_setting('timescaledb.max_background_workers')::float
    UNION ALL
    SELECT now_ts, 'worker.running', '', '', count(*)::float
    FROM pg_stat_activity
    WHERE backend_type LIKE '%worker%' OR application_name LIKE 'TimescaleDB Background Job%';
END;
$$;

-- -------------------------------------------------------------------------------------
-- Schedule. Re-running this file must not stack up duplicate jobs.
-- -------------------------------------------------------------------------------------
DO $$
DECLARE
    j record;
BEGIN
    FOR j IN
        SELECT job_id FROM timescaledb_information.jobs
        WHERE proc_schema = 'monitoring' AND proc_name IN ('sample_fast', 'sample_slow')
    LOOP
        PERFORM delete_job(j.job_id);
    END LOOP;
END;
$$;

SELECT add_job('monitoring.sample_fast', INTERVAL '10 seconds');
SELECT add_job('monitoring.sample_slow', INTERVAL '5 minutes');

-- Keep a week. At roughly 60 fast rows every 10s plus 100 slow rows every 5 min this is
-- a few million narrow rows -- small next to the result tables it watches.
SELECT remove_retention_policy('monitoring.pg_samples', if_exists => TRUE);
SELECT add_retention_policy('monitoring.pg_samples', INTERVAL '7 days');

-- Grafana reads this schema through the same perfana user as the rest of the dashboards.
GRANT USAGE ON SCHEMA monitoring TO perfana;
GRANT SELECT ON ALL TABLES IN SCHEMA monitoring TO perfana;
