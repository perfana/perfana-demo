#!/usr/bin/env bash

set -o errexit

LOAD_TEST_DIR=loadtest
LOAD_TEST_TAR=$LOAD_TEST_DIR/loadtest-gatling.tar.gz

if [ ! -d "$LOAD_TEST_DIR" ]; then
  echo "Untar $LOAD_TEST_TAR in $LOAD_TEST_DIR"
  mkdir -p "$LOAD_TEST_DIR"
  tar xvfz "$LOAD_TEST_TAR" -C "$LOAD_TEST_DIR"
elif [ -d "$LOAD_TEST_DIR/src" ]; then
  echo "Creating new $LOAD_TEST_TAR from $LOAD_TEST_DIR/src"
  tar cvzf "$LOAD_TEST_TAR" -C "$LOAD_TEST_DIR" src
else
  echo "Error: $LOAD_TEST_DIR/src directory not found"
  exit 1
fi



