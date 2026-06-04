#!/usr/bin/env bash
# Report migrations present in supabase/migrations/ but not yet applied to
# $DATABASE_URL (drift → run apply_migrations.sh), and any applied version
# with no file (orphan). Exits non-zero on either (issue #20). Local only —
# no DB credential in CI.
set -euo pipefail

: "${DATABASE_URL:?set DATABASE_URL to the Supabase direct connection string}"
command -v psql >/dev/null || { echo "psql not found (install postgresql-client)" >&2; exit 1; }

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/migrations" && pwd)"

files="$(for f in "$dir"/*.sql; do basename "$f" | sed -E 's/^([0-9]+)_.*/\1/'; done | sort -u)"
applied="$(psql "$DATABASE_URL" -tAq -c \
  "select version from public._ccrl_migrations" 2>/dev/null | sort -u || true)"

drift="$(comm -23 <(printf '%s\n' "$files") <(printf '%s\n' "$applied"))"
orphan="$(comm -13 <(printf '%s\n' "$files") <(printf '%s\n' "$applied"))"

rc=0
if [ -n "$drift" ]; then
  echo "DRIFT — in repo but NOT applied to live (run ./supabase/apply_migrations.sh):"
  echo "$drift" | sed 's/^/  /'
  rc=1
fi
if [ -n "$orphan" ]; then
  echo "ORPHAN — applied on live but no migration file:"
  echo "$orphan" | sed 's/^/  /'
  rc=1
fi
[ "$rc" -eq 0 ] && echo "✓ in sync — every migration is applied."
exit "$rc"
