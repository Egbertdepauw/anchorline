#!/usr/bin/env bash
# Fails if any migration contains non-idempotent DDL. No database needed —
# a pure static check, safe to run in CI. See supabase/README.md for the
# idempotency rule every migration must follow (issue #20).
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/migrations" && pwd)"
fail=0

for f in "$dir"/*.sql; do
  name="$(basename "$f")"

  # Rules 1–4: these statements must carry IF [NOT] EXISTS on the same line.
  while IFS=: read -r ln text; do
    [ -z "$ln" ] && continue
    echo "  $name:$ln  $(echo "$text" | sed 's/^[[:space:]]*//')"
    fail=1
  done < <(
    grep -niE 'create table |create (unique )?index |add column |drop column ' "$f" \
      | grep -viE 'if not exists|if exists' || true
  )

  # Rule 6: an `alter publication ... add table` must be guarded — only allowed
  # inside an EXECUTE string (the DO-block form). A bare ALTER is flagged.
  while IFS=: read -r ln text; do
    [ -z "$ln" ] && continue
    if ! echo "$text" | grep -qiE 'execute'; then
      echo "  $name:$ln  (unguarded) $(echo "$text" | sed 's/^[[:space:]]*//')"
      fail=1
    fi
  done < <(grep -niE 'alter publication .* add table' "$f" || true)

  # Rule 5: every `create policy` needs a matching `drop policy if exists`.
  creates="$(grep -ciE 'create policy' "$f" || true)"
  drops="$(grep -ciE 'drop policy if exists' "$f" || true)"
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
echo "OK: all migrations are idempotent."
