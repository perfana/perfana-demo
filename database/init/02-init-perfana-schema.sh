#!/bin/bash
set -e

# Connect to the main perfana database and load schema
echo "Loading Perfana schema into $POSTGRES_DB database..."

# Load schema into the database specified by POSTGRES_DB
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname="$POSTGRES_DB" <<-EOSQL
    \i /docker-entrypoint-initdb.d/03-perfana-schema.sql
EOSQL

echo "Perfana schema loaded successfully"
