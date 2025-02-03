#!/bin/bash

# Wait for InfluxDB to start
sleep 10

# Create databases
influx -execute 'CREATE DATABASE gatling3'
influx -execute 'CREATE RETENTION POLICY "30d" ON gatling3 DURATION 30d REPLICATION 1 DEFAULT'
influx -execute 'CREATE DATABASE jmeter'
influx -execute 'CREATE RETENTION POLICY "30d" ON jmeter DURATION 30d REPLICATION 1 DEFAULT'
influx -execute 'CREATE DATABASE telegraf'
influx -execute 'CREATE RETENTION POLICY "30d" ON telegraf DURATION 30d REPLICATION 1 DEFAULT'

# Create continuous queries
influx -execute 'CREATE CONTINUOUS QUERY gatling_cq_failed_rps1 ON gatling3 BEGIN SELECT CUMULATIVE_SUM(count("duration")) as "failed" INTO "gatling-throughput" FROM "30d"."requests" WHERE "result" = 'KO' GROUP BY time(10s),result,simulation,testEnvironment,systemUnderTest END'
influx -execute 'CREATE CONTINUOUS QUERY gatling_cq_total_rps ON gatling3 BEGIN SELECT CUMULATIVE_SUM(count("duration")) as "total" INTO "gatling-throughput" FROM "30d"."requests" GROUP BY time(10s),result,simulation,testEnvironment,systemUnderTest END'
influx -execute 'CREATE CONTINUOUS QUERY gatling_cq_response_time_percentiles ON gatling3 RESAMPLE EVERY 10s FOR 30s BEGIN SELECT percentile("duration", 50) AS "cq_50pct_response_time", percentile("duration", 90) AS "cq_90pct_response_time", percentile("duration", 95) AS "cq_95pct_response_time", percentile("duration", 99) AS "cq_99pct_response_time", max("duration") AS "cq_max_response_time", min("duration") AS "cq_min_response_time", mean("duration") AS "cq_mean_response_time", stddev("duration") AS "cq_stddev_response_time", count("duration") AS "cq_request_count" INTO "gatling-percentiles" FROM "30d"."requests" GROUP BY time(10s),result,simulation,testEnvironment,systemUnderTest,"name" END'
influx -execute 'CREATE CONTINUOUS QUERY jmeter_cq_failed_rps1 ON jmeter BEGIN SELECT CUMULATIVE_SUM(count("duration")) as "failed" INTO "jmeter-throughput" FROM "30d"."requests" WHERE "success" = 'false' GROUP BY time(10s),success,testEnvironment,systemUnderTest END'
influx -execute 'CREATE CONTINUOUS QUERY jmeter_cq_total_rps ON jmeter BEGIN SELECT CUMULATIVE_SUM(count("duration")) as "total" INTO "jmeter-throughput" FROM "30d"."requests" GROUP BY time(10s),testEnvironment,systemUnderTest END'
influx -execute 'CREATE CONTINUOUS QUERY jmeter_cq_response_time_percentiles ON jmeter BEGIN SELECT percentile("duration", 50) AS "cq_50pct_response_time", percentile("duration", 90) AS "cq_90pct_response_time", percentile("duration", 95) AS "cq_95pct_response_time", percentile("duration", 99) AS "cq_99pct_response_time", max("duration") AS "cq_max_response_time", min("duration") AS "cq_min_response_time", mean("duration") AS "cq_mean_response_time", stddev("duration") AS "cq_stddev_response_time", count("duration") AS "cq_request_count" INTO "jmeter-percentiles" FROM "30d"."requests" GROUP BY time(10s),success,testEnvironment,systemUnderTest,"label" END'