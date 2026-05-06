#!/bin/sh
set -eu
echo "lab-driver starting: rps=${DRIVER_RPS:-1500} sut=${DRIVER_SUT:-?} scenario=${DRIVER_SCENARIO:-?} testRunId=${DRIVER_TEST_RUN_ID:-?}"
exec java -XX:+UseG1GC -XX:MaxRAMPercentage=75 -jar /app/lab-driver.jar
