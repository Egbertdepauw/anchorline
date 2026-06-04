#!/usr/bin/env bash
# Apply every migration (idempotent) to $DATABASE_URL, recording each version
# in public._ccrl_migrations. Safe to re-run — that's the convergence
# guarantee and the fresh-project-recreate path (issue #20).
#
# DATABASE_URL must be the Supabase DIRECT/session connection string (not the
# pooler) — DDL + ALTER PUBLICATION need a direct session.
set -euo pipefail

: "${DATABASE_URL:?set DATABASE_URL to the Supabase direct connection string}"
command -v psql >/dev/null || { echo "psql not found (install postgresql-client)" >&2; exit 1; }

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/migrations" && pwd)"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -c \
  "create table if not exists public._ccrl_migrations (
     version text primary key,
     applied_at timestamptz not null default now()
   );"

for f in "$dir"/*.sql; do
  version="$(basename "$f" | sed -E 's/^([0-9]+)_.*/\1/')"
  echo "→ applying $version ($(basename "$f"))"
  # Each migration + its version record in ONE transaction: a failure rolls
  # the whole thing back, never leaving a half-applied migration.
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q --single-transaction \
    -f "$f" \
    -c "insert into public._ccrl_migrations(version) values ('$version')
        on conflict (version) do nothing;"
done

echo "✓ applied ${0##*/}: $(ls "$dir"/*.sql | wc -l | tr -d ' ') migrations"
