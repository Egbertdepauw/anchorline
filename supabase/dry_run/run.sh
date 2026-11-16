#!/usr/bin/env bash
# Dry-runs every migration on a throwaway local Postgres (Docker), with the
# Supabase-only objects stubbed. No Supabase project is touched.
#
#   supabase/dry_run/run.sh      # exit 0 = pass
#
# 1. dryrun_main: stub, all migrations twice (idempotency), then every
#    checks/*_check.sql. Check files own their transaction (begin; ... rollback;).
# 2. dryrun_guard: the 0027 guard must refuse and roll back a database that
#    holds a cross-owner child row.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
migrations="$here/../migrations"
name="anchorline-dryrun-$$"
port=55433
export PGPASSWORD=dryrun
export PGOPTIONS='-c client_min_messages=warning'

command -v docker >/dev/null || { echo "docker not found" >&2; exit 1; }
command -v psql >/dev/null || { echo "psql not found" >&2; exit 1; }

cleanup() { docker rm -f "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --rm --name "$name" -p "$port:5432" \
  -e POSTGRES_PASSWORD=dryrun postgres:17-alpine -c wal_level=logical >/dev/null

ext_dir=/usr/local/share/postgresql/extension
docker cp "$here/stub/pg_cron.control" "$name:$ext_dir/pg_cron.control"
docker cp "$here/stub/pg_cron--1.0.sql" "$name:$ext_dir/pg_cron--1.0.sql"

# The image restarts Postgres once during init, so pg_isready alone can pass
# too early. Wait until a real query works, several times in a row.
ok=0
for _ in $(seq 1 60); do
  if psql -h localhost -p "$port" -U postgres -d postgres -Atqc 'select 1' >/dev/null 2>&1; then
    ok=$((ok + 1))
    [ "$ok" -ge 3 ] && break
  else
    ok=0
  fi
  sleep 1
done
[ "$ok" -ge 3 ] || { echo "postgres did not become ready" >&2; exit 1; }

run() { # db, file...  (single transaction, stop on error)
  local db="$1"; shift
  psql -h localhost -p "$port" -U postgres -d "$db" -v ON_ERROR_STOP=1 -q \
    --single-transaction -f "$1" -o /dev/null
}
run_plain() { # db, file (the file owns its own transaction)
  psql -h localhost -p "$port" -U postgres -d "$1" -v ON_ERROR_STOP=1 -q -f "$2" -o /dev/null
}
mkdb() {
  psql -h localhost -p "$port" -U postgres -d postgres -v ON_ERROR_STOP=1 -q \
    -c "create database $1"
  psql -h localhost -p "$port" -U postgres -d "$1" -v ON_ERROR_STOP=1 -q \
    -f "$here/stub/supabase_stub.sql" -o /dev/null
}

echo "== dryrun_main: migrations, twice =="
mkdb dryrun_main
for pass in 1 2; do
  for f in "$migrations"/*.sql; do
    echo "  pass $pass: $(basename "$f")"
    run dryrun_main "$f"
  done
done

shopt -s nullglob
for f in "$here"/checks/*_check.sql; do
  echo "== check: $(basename "$f") =="
  run_plain dryrun_main "$f"
done

setup="$here/scenarios/0027_guard_setup.sql"
if [ -f "$setup" ]; then
  echo "== dryrun_guard: 0027 must refuse a cross-owner child row =="
  mkdb dryrun_guard
  for f in "$migrations"/*.sql; do
    base="$(basename "$f")"
    [[ "$base" < "0027" ]] || continue
    run dryrun_guard "$f"
  done
  run dryrun_guard "$setup"
  if run dryrun_guard "$migrations"/0027_*.sql 2>"$here/.guard_err"; then
    echo "FAIL: 0027 applied on a database with a cross-owner child row" >&2
    rm -f "$here/.guard_err"
    exit 1
  fi
  if ! grep -q '0027 refused' "$here/.guard_err"; then
    echo "FAIL: 0027 failed, but not on its guard:" >&2
    sed 's/^/    /' "$here/.guard_err" >&2
    rm -f "$here/.guard_err"
    exit 1
  fi
  echo "  0027 refused, as it should:"
  sed 's/^/    /' "$here/.guard_err"
  rm -f "$here/.guard_err"
  run_plain dryrun_guard "$here/scenarios/0027_guard_assert.sql"
else
  echo "(notice) scenarios/0027_guard_setup.sql not present: skipping the guard step"
fi

echo "✓ dry run passed"
