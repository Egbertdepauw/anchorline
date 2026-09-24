#!/usr/bin/env bash
# Fails if any migration contains non-idempotent DDL. No database needed —
# a pure static check, safe to run in CI. See supabase/README.md for the
# idempotency rule every migration must follow (issue #20).
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/migrations" && pwd)"
[ -d "$dir" ] || { echo "migrations dir not found: $dir" >&2; exit 1; }
shopt -s nullglob
sqls=("$dir"/*.sql)
[ "${#sqls[@]}" -gt 0 ] || { echo "no migration .sql files found in $dir" >&2; exit 1; }
fail=0

for f in "${sqls[@]}"; do
  name="$(basename "$f")"

  # Rules 1–4: these statements must carry IF [NOT] EXISTS on the same line.
  while IFS=: read -r ln text; do
    [ -z "$ln" ] && continue
    echo "  $name:$ln  $(echo "$text" | sed 's/^[[:space:]]*//')"
    fail=1
  done < <(
    grep -niE 'create table |create (unique )?index |add column |drop column ' "$f" \
      | grep -viE 'if not exists|if exists' \
      | grep -vE '^[0-9]+:[[:space:]]*--' || true
  )

  # Rule 6: an `alter publication ... add table` must be guarded — only allowed
  # inside an EXECUTE string (the DO-block form). A bare ALTER is flagged.
  while IFS=: read -r ln text; do
    [ -z "$ln" ] && continue
    if ! echo "$text" | grep -qiE 'execute'; then
      echo "  $name:$ln  (unguarded) $(echo "$text" | sed 's/^[[:space:]]*//')"
      fail=1
    fi
  done < <(grep -niE '(alter|create) publication ' "$f" | grep -vE '^[0-9]+:[[:space:]]*--' || true)

  # Rule 5: every `create policy` needs a matching `drop policy if exists`.
  creates="$(grep -vE '^[[:space:]]*--' "$f" | grep -ciE 'create policy' || true)"
  drops="$(grep -vE '^[[:space:]]*--' "$f" | grep -ciE 'drop policy if exists' || true)"
  if [ "${creates:-0}" -gt "${drops:-0}" ]; then
    echo "  $name  create policy ($creates) without matching drop policy if exists ($drops)"
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "FAIL: non-idempotent migration statements found (issue #20)." >&2
  exit 1
fi

# Rule 7 (cross-file): every created table needs an explicit Data API
# decision for `authenticated`, either a `grant ... to authenticated` or a
# `revoke ... from authenticated`, in some migration. Supabase no longer
# auto-grants new public tables (issue #76), so a missing grant = a table
# the app can't reach. Grant/revoke statements must be single-line.
all_sql="$(cat "${sqls[@]}" | { grep -vE '^[[:space:]]*--' || true; } | tr '[:upper:]' '[:lower:]')"
created="$(printf '%s\n' "$all_sql" \
  | sed -nE 's/^[[:space:]]*create table if not exists[[:space:]]+(public\.)?([a-z0-9_]+).*/\2/p' \
  | sort -u)"
# Object list between ` on [table] ` and ` to|from `, split on commas.
decided="$(printf '%s\n' "$all_sql" \
  | { grep -E '^[[:space:]]*(grant[[:space:]].*[[:space:]]to|revoke[[:space:]].*[[:space:]]from)[[:space:]].*authenticated' || true; } \
  | sed -E 's/.*[[:space:]]on[[:space:]]+(table[[:space:]]+)?(.*)[[:space:]]+(to|from)[[:space:]].*/\2/' \
  | tr ',' '\n' | sed -E 's/^[[:space:]]*(public\.)?//; s/[[:space:]]*$//' \
  | sort -u)"
missing="$(comm -23 <(printf '%s\n' "$created") <(printf '%s\n' "$decided"))"
if [ -n "$missing" ]; then
  echo "$missing" | sed 's/^/  no grant\/revoke to authenticated: /'
  echo ""
  echo "FAIL: tables without an explicit Data API grant (issue #76). Add e.g." >&2
  echo "  grant select, insert, update, delete on table public.<t> to authenticated, service_role;" >&2
  exit 1
fi
echo "OK: all migrations are idempotent and every table has explicit Data API grants."
