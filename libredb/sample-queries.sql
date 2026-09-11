-- Sample queries for the Perfana database. All verified against this dataset.
-- Paste into LibreDB Studio (http://localhost:3005), connection "Perfana (TimescaleDB)".

-- 1. Latency percentiles per transaction for one run
SELECT transaction_name,
       count(*)                                                          AS n,
       round(avg(response_time))                                         AS avg_ms,
       percentile_disc(0.95) WITHIN GROUP (ORDER BY response_time)       AS p95,
       percentile_disc(0.99) WITHIN GROUP (ORDER BY response_time)       AS p99,
       round(100.0 * count(*) FILTER (WHERE NOT success) / count(*), 2)  AS err_pct
FROM requests_raw
WHERE test_run_id = 'WBS-acceptatie-loadtest_perfana-00013'
GROUP BY 1 ORDER BY p95 DESC LIMIT 20;

-- 2. What ADAPT flagged as a regression
SELECT panel_title, metric_name, conclusion->>'label' AS label
FROM ds_adapt_results
WHERE test_run_id = 'WBS-acceptatie-loadtest_perfana-00013'
  AND conclusion->>'label' = 'regression'
ORDER BY panel_title LIMIT 50;

-- 3. Throughput and latency over time (TimescaleDB time_bucket)
SELECT time_bucket('1 minute', time) AS minute,
       count(*)                      AS requests,
       round(avg(response_time))     AS avg_ms,
       count(*) FILTER (WHERE NOT success) AS errors
FROM requests_raw
WHERE test_run_id = 'WBS-acceptatie-loadtest_perfana-00013'
GROUP BY 1 ORDER BY 1;

-- 4. Run-vs-run regression hunt: which transactions got slower?
WITH a AS (SELECT transaction_name, count(*) n,
                  percentile_disc(0.95) WITHIN GROUP (ORDER BY response_time) p95
           FROM requests_raw WHERE test_run_id='WBS-acceptatie-loadtest_perfana-00012' GROUP BY 1),
     b AS (SELECT transaction_name,
                  percentile_disc(0.95) WITHIN GROUP (ORDER BY response_time) p95
           FROM requests_raw WHERE test_run_id='WBS-acceptatie-loadtest_perfana-00016' GROUP BY 1)
SELECT a.transaction_name, a.p95 AS base_p95, b.p95 AS new_p95,
       round(100.0*(b.p95-a.p95)/nullif(a.p95,0),1) AS pct_change
FROM a JOIN b USING (transaction_name)
WHERE a.n > 50 AND b.p95 > a.p95 * 1.2
ORDER BY pct_change DESC LIMIT 25;

-- 5. Storage: hypertables and chunk counts
SELECT hypertable_name, num_chunks,
       pg_size_pretty(hypertable_size(format('%I.%I', hypertable_schema, hypertable_name)::regclass)) AS size
FROM timescaledb_information.hypertables
ORDER BY hypertable_size(format('%I.%I', hypertable_schema, hypertable_name)::regclass) DESC;

-- 6. Longest-lived transactions seen by the monitoring sampler
--    (the metric behind the 600s worker transactions in the PostgreSQL health dashboard)
SELECT source, round(max(value)::numeric, 1) AS peak_seconds
FROM monitoring.pg_samples
WHERE metric = 'conn.xact_age_s'
GROUP BY 1 ORDER BY peak_seconds DESC LIMIT 15;

-- 7. Hypertable sizes, and why the object browser disagrees.
--    LibreDB (and any plain catalogue read) sizes the *parent* relation, which is
--    empty for a hypertable -- every row lives in chunks under _timescaledb_internal,
--    a schema the browser does not list. So ds_metrics shows as ~40 kB rather than 7 GB.
--    hypertable_size() is the only reading that is correct.
SELECT h.hypertable_schema || '.' || h.hypertable_name AS hypertable,
       h.num_chunks,
       pg_size_pretty(pg_total_relation_size(
         format('%I.%I', h.hypertable_schema, h.hypertable_name)::regclass))  AS parent_only,
       pg_size_pretty(hypertable_size(
         format('%I.%I', h.hypertable_schema, h.hypertable_name)::regclass))  AS real_total,
       (SELECT count(*) FROM timescaledb_information.chunks c
         WHERE c.hypertable_name = h.hypertable_name AND c.is_compressed)     AS compressed_chunks
FROM timescaledb_information.hypertables h
ORDER BY hypertable_size(
  format('%I.%I', h.hypertable_schema, h.hypertable_name)::regclass) DESC;
