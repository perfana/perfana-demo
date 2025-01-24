#!/bin/sh
# Create indexes
curl -X 'POST' \
  'http://localhost:8080/manage/createIndexes?panels=true&metrics=true&metricStatistics=true&controlGroups=true&controlGroupStatistics=true&trackedDifferences=true&adaptInput=true&adaptResults=true&adaptConclusion=true&adaptTrackedResults=true' \
  -H 'accept: application/json' \
  -d ''
# Create schemas
curl -X 'POST' \
  'http://localhost:8080/manage/createSchemas?panels=true&metrics=true&metricStatistics=true&controlGroupStatistics=true&trackedDifferences=true&adaptInput=true&adaptResults=true&adaptTrackedResults=true&adaptConclusion=true' \
  -H 'accept: application/json' \
  -d ''
