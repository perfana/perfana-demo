#!/usr/bin/env bash
# Writes pgbouncer/userlist.txt from POSTGRES_PASSWORD in .env.
#
# The password is stored in plain text on purpose. With auth_type = scram-sha-256
# PgBouncer hashes it to authenticate incoming clients AND needs it to log in to
# PostgreSQL itself, which also runs scram-sha-256. A stored SCRAM verifier can only
# do the first half: PgBouncer cannot use a verifier to authenticate onwards to the
# server. The file is git-ignored; keep it readable only by the Docker host user.
#
# Re-run this whenever POSTGRES_PASSWORD changes.
set -euo pipefail

cd "$(dirname "$0")/.."

USER="${PGBOUNCER_USER:-perfana}"
PASS="${POSTGRES_PASSWORD:-}"

if [ -z "$PASS" ] && [ -f .env ]; then
  PASS="$(grep -E '^POSTGRES_PASSWORD=' .env | head -1 | cut -d= -f2- | sed 's/^"//; s/"$//')"
fi

if [ -z "$PASS" ]; then
  echo "POSTGRES_PASSWORD not set and not found in .env" >&2
  exit 1
fi

mkdir -p pgbouncer
umask 077
printf '"%s" "%s"\n' "$USER" "$PASS" > pgbouncer/userlist.txt
echo "Wrote pgbouncer/userlist.txt for user '$USER'"
