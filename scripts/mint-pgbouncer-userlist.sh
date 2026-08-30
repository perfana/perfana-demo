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

# Docker creates a root-owned directory at a bind-mount source that does not exist,
# so starting the pgbouncer profile before this script has ever run leaves a
# directory here. Writing to it fails with a confusing EISDIR.
if [ -d pgbouncer/userlist.txt ]; then
  echo "pgbouncer/userlist.txt is a directory — Docker created it for the missing bind mount." >&2
  echo "Remove it and re-run:  sudo rmdir pgbouncer/userlist.txt" >&2
  exit 1
fi

umask 077
printf '"%s" "%s"\n' "$USER" "$PASS" > pgbouncer/userlist.txt

# edoburu/pgbouncer runs as uid 70 (postgres), not root. A 0600 file owned by the
# host user is unreadable to it and PgBouncer dies on startup with
# "permission denied" opening auth_file. Hand the file to uid 70 where we can;
# fall back to world-readable so the container still starts.
if chown 70:70 pgbouncer/userlist.txt 2>/dev/null; then
  chmod 640 pgbouncer/userlist.txt
  echo "Wrote pgbouncer/userlist.txt for user '$USER' (owner 70:70, mode 640)"
else
  chmod 644 pgbouncer/userlist.txt
  echo "Wrote pgbouncer/userlist.txt for user '$USER' (mode 644)"
  echo "warning: could not chown to uid 70 — needs root. Mode 644 lets the container" >&2
  echo "         read it, but the password is now host-world-readable. Re-run with" >&2
  echo "         sudo for owner 70:70 / mode 640." >&2
fi
