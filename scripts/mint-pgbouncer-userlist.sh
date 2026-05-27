#!/usr/bin/env bash
# Generates pgbouncer/userlist.txt with MD5-hashed credentials.
# pgbouncer md5 format: "md5" + md5(password + username), all hex.
set -euo pipefail

USER="${1:-perfana}"
PASS="${2:?usage: $0 <user> <password>}"
OUT="${3:-pgbouncer/userlist.txt}"

HASH="md5$(printf '%s%s' "$PASS" "$USER" | md5sum | cut -d' ' -f1)"
printf '"%s" "%s"\n' "$USER" "$HASH" > "$OUT"
echo "Wrote $OUT for user '$USER'"
