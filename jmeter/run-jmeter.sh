#!/bin/sh
# Run JMeter test plans matching the JMETER_TEST glob pattern.
# Called by perfana-cli as an onStartTest command event.
# Arguments: $1 = testRunId (from perfana-cli __testRunId__ substitution)

TEST_RUN_ID="$1"

for f in /tests/src/test/jmeter/${JMETER_TEST}; do
  breaktest.sh -n -t "$f" \
    -JHOST=afterburner-fe \
    -JPORT=8080 \
    -JPROTOCOL=http \
    -JTHREADS=10 \
    -JRAMP_TIME=60 \
    -JDURATION=360 \
    -JrunId="$TEST_RUN_ID" \
    -Jtest.testRunId="$TEST_RUN_ID" \
    -JtimescaleHost=host.docker.internal \
    -JtimescalePassword=perfana \
    -j "/tests/target/jmeter-$(basename "$f" .jmx).log" \
    -l "/tests/target/results/$(basename "$f" .jmx).jtl" \
    -e -o "/tests/target/reports/$(basename "$f" .jmx)" &
done

wait
