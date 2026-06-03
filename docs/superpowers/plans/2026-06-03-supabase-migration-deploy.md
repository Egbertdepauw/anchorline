# Supabase Migration Deploy + Drift Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A scripted, idempotent path from `supabase/migrations/*.sql` to the live database, plus a local drift check, so migrations can't be silently forgotten (the #20 process gap that left 0009 unapplied).

**Architecture:** Bash + `psql` scripts under `supabase/` (no Supabase CLI, nothing new in pubspec). All migrations are rewritten to be idempotent so the full set re-runs to converge (also the fresh-recreate path). A repo-local idempotency **lint** (grep-based, no DB) is the automated regression gate; a `public._ccrl_migrations` tracking table + an apply script and a drift-check script handle deploy + visibility. Live-DB verification is the manual twice-run documented in the spec.

**Tech Stack:** PostgreSQL/`psql`, bash, GitHub Actions (optional lint wiring).

**Spec:** `docs/superpowers/specs/2026-06-03-supabase-migration-deploy-design.md`

---

## File Structure

- **Create** `supabase/lint_migrations.sh` — idempotency lint (no DB). The automated test.
- **Create** `supabase/apply_migrations.sh` — apply all migrations to `$DATABASE_URL`, record versions.
- **Create** `supabase/check_migrations.sh` — drift check (files vs `_ccrl_migrations`).
- **Create** `supabase/README.md` — usage, idempotency rule, fresh-recreate + twice-run acceptance test.
- **Modify** migrations `0001, 0003, 0004, 0005, 0006, 0007, 0010, 0011, 0012, 0013, 0014` — make idempotent. (`0002`, `0008`, `0009` already are; leave them.)
- **Modify** `.github/workflows/check.yml` — add a DB-free `lint migrations` step.

**Idempotency transform rules** (the lint enforces these; apply them everywhere):

| Found | Replace with |
|---|---|
| `create table T (` | `create table if not exists T (` |
| `create index I ...` / `create unique index I ...` | `create index if not exists I ...` / `create unique index if not exists I ...` |
| `... add column C ...` | `... add column if not exists C ...` (every column in a multi-column `ALTER TABLE`) |
| `alter table T drop column C` | `alter table T drop column if exists C` |
| `create policy "P" on T ...` | precede with `drop policy if exists "P" on T;` (same name + table) |
| `alter publication powersync add table T[, T2];` | a guarded `DO` block per table (see Task 3) |

Preserve existing casing per file (0001–0009/0012 are lowercase; 0010/0011/0013/0014 uppercase) and keep all `NOTIFY pgrst, 'reload schema';` lines.

---

### Task 1: Idempotency lint (the automated gate)

**Files:**
- Create: `supabase/lint_migrations.sh`

- [ ] **Step 1: Write the lint script**

Create `supabase/lint_migrations.sh`:

```bash
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
```

- [ ] **Step 2: Make it executable and run it — expect FAIL**

```bash
chmod +x supabase/lint_migrations.sh
./supabase/lint_migrations.sh
```
Expected: non-zero exit, listing offenders in `0001, 0003, 0004, 0005, 0006, 0007, 0010, 0011, 0012, 0013, 0014` (e.g. `0010_display_deco_algorithm.sql:2 ADD COLUMN display_deco_algorithm TEXT;`).

- [ ] **Step 3: Commit the lint**

```bash
git add supabase/lint_migrations.sh
git commit -m "test(supabase): add idempotency lint for migrations (#20)"
```

---

### Task 2: Make the ADD COLUMN / DROP COLUMN migrations idempotent

**Files:**
- Modify: `supabase/migrations/0005_dive_annotations_equipment.sql`, `0006_dive_sensor_calibration.sql`, `0007_dive_annotation_conditions.sql`, `0010_display_deco_algorithm.sql`, `0011_dive_bailout_carry.sql` (the `drop column` line only)

- [ ] **Step 1: Edit 0005** — in the `alter table dive_annotations` block, change each of the five `add column X type` to `add column if not exists X type`:
  `add column suit text,` → `add column if not exists suit text,` (and `undersuit`, `weight_system`, `dpv`, `camera`).

- [ ] **Step 2: Edit 0006** — `add column sensor_calibration_json text;` → `add column if not exists sensor_calibration_json text;`

- [ ] **Step 3: Edit 0007** — change each of the eight `add column X` (visibility, wavesize, `"current"`, surge, chill, air_temp_c, water_temp_c, weights_json) to `add column if not exists X` (keep types + the quoted `"current"`).

- [ ] **Step 4: Edit 0010** — replace:
```sql
ALTER TABLE dive_annotations
ADD COLUMN display_deco_algorithm TEXT;
```
with:
```sql
ALTER TABLE dive_annotations
ADD COLUMN IF NOT EXISTS display_deco_algorithm TEXT;
```

- [ ] **Step 5: Edit 0011 (drop only)** — replace `ALTER TABLE cylinders DROP COLUMN gas_mix;` with `ALTER TABLE cylinders DROP COLUMN IF EXISTS gas_mix;` (the rest of 0011 is handled in Task 3).

- [ ] **Step 6: Run the lint — these files must stop being reported**

```bash
./supabase/lint_migrations.sh
```
Expected: still FAIL overall, but no `0005/0006/0007/0010` lines and no `0011` `drop column` line remain (the remaining `0011/0001/0003/0004/0012/0013/0014` create/policy/publication offenders persist — fixed in Task 3).

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/0005_dive_annotations_equipment.sql supabase/migrations/0006_dive_sensor_calibration.sql supabase/migrations/0007_dive_annotation_conditions.sql supabase/migrations/0010_display_deco_algorithm.sql supabase/migrations/0011_dive_bailout_carry.sql
git commit -m "fix(supabase): idempotent ADD/DROP COLUMN migrations (#20)"
```

---

### Task 3: Make the CREATE TABLE / INDEX / POLICY / PUBLICATION migrations idempotent

**Files:**
- Modify: `0001_initial_schema.sql`, `0003_dives_and_samples.sql`, `0004_dive_attachments.sql`, `0011_dive_bailout_carry.sql`, `0012_usage_events.sql`, `0013_dive_plans.sql`, `0014_dive_merge_links.sql`

Apply the transform rules from the File Structure table. Specifics:

- [ ] **Step 1: CREATE TABLE / CREATE INDEX → add `IF NOT EXISTS`** in every listed file. Examples:
  - `0001`: `create table dive_annotations (` → `create table if not exists dive_annotations (` (and `cylinders`, `oxygen_cells`, `scrubber_sessions`, `pressure_mappings`, `dive_cylinders`, `dive_computers`).
  - `0003`: `create table dives (`, `create table dive_samples (` → `... if not exists ...`; `create index dives_owner_id_idx on dives (owner_id);` → `create index if not exists dives_owner_id_idx on dives (owner_id);`; same for `dive_samples_owner_id_idx`.
  - `0004`: `create table dive_attachments (` and the 3 indexes (`dive_attachments_owner_id_idx`, `dive_attachments_parent_idx`, `dive_attachments_storage_key_idx`).
  - `0011`: `CREATE TABLE dive_bailout_carry (`, `CREATE INDEX idx_dive_bailout_carry_owner_dive`.
  - `0012`: `create table usage_events (`, `create index usage_events_owner_created`, `create index usage_events_name_created`.
  - `0013`: `CREATE TABLE dive_plans (`, `CREATE UNIQUE INDEX idx_dive_plans_owner_draft`, `CREATE INDEX idx_dive_plans_owner_updated`.
  - `0014`: `CREATE TABLE dive_merge_links (`, `CREATE INDEX idx_dive_merge_links_owner_group`.

- [ ] **Step 2: CREATE POLICY → precede with DROP POLICY IF EXISTS** (same name + table). For each `create policy` in the listed files, insert a drop line immediately before it. The exact insertions:
  - `0001` (7 policies, all named `"owner_full_access"`, one per table) — before each `create policy "owner_full_access" on T for all`, add `drop policy if exists "owner_full_access" on T;` with the matching T (`dive_annotations`, `cylinders`, `oxygen_cells`, `scrubber_sessions`, `pressure_mappings`, `dive_cylinders`, `dive_computers`).
  - `0003` — before `create policy "owner_full_access" on dives`, add `drop policy if exists "owner_full_access" on dives;`; before the `dive_samples` one, add `drop policy if exists "owner_full_access" on dive_samples;`.
  - `0004` — `drop policy if exists "owner_full_access" on dive_attachments;`
  - `0011` — `DROP POLICY IF EXISTS "owner can rw" ON dive_bailout_carry;`
  - `0012` — `drop policy if exists "owner_insert_only" on usage_events;`
  - `0013` — `DROP POLICY IF EXISTS "owner can rw" ON dive_plans;`
  - `0014` — `DROP POLICY IF EXISTS "owner can rw" ON dive_merge_links;`

- [ ] **Step 3: ALTER PUBLICATION → guarded DO block (one per table).** Replace each bare `alter publication powersync add table ...;` with a guard.
  - `0003` — replace `alter publication powersync add table dives, dive_samples;` with:
```sql
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'powersync' and schemaname = 'public' and tablename = 'dives') then
    execute 'alter publication powersync add table public.dives';
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'powersync' and schemaname = 'public' and tablename = 'dive_samples') then
    execute 'alter publication powersync add table public.dive_samples';
  end if;
end $$;
```
  - `0004` — same block for `dive_attachments`.
  - `0011` — replace `ALTER PUBLICATION powersync ADD TABLE "public"."dive_bailout_carry";` with:
```sql
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'powersync' and schemaname = 'public' and tablename = 'dive_bailout_carry') then
    execute 'alter publication powersync add table public.dive_bailout_carry';
  end if;
end $$;
```
  - `0013` — same block for `dive_plans`.
  - `0014` — same block for `dive_merge_links`.

- [ ] **Step 4: Run the lint — must now PASS**

```bash
./supabase/lint_migrations.sh
```
Expected: `OK: all migrations are idempotent.` (exit 0).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0001_initial_schema.sql supabase/migrations/0003_dives_and_samples.sql supabase/migrations/0004_dive_attachments.sql supabase/migrations/0011_dive_bailout_carry.sql supabase/migrations/0012_usage_events.sql supabase/migrations/0013_dive_plans.sql supabase/migrations/0014_dive_merge_links.sql
git commit -m "fix(supabase): idempotent CREATE TABLE/INDEX/POLICY/PUBLICATION migrations (#20)"
```

---

### Task 4: Apply script + tracking table

**Files:**
- Create: `supabase/apply_migrations.sh`

- [ ] **Step 1: Write the apply script**

Create `supabase/apply_migrations.sh`:

```bash
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
```

- [ ] **Step 2: Static sanity check (no DB)**

```bash
chmod +x supabase/apply_migrations.sh
bash -n supabase/apply_migrations.sh && echo "syntax OK"
# Without DATABASE_URL it must exit with the clear message:
unset DATABASE_URL; ./supabase/apply_migrations.sh; echo "exit=$?"
```
Expected: `syntax OK`, then `set DATABASE_URL to the Supabase direct connection string` and a non-zero exit.

- [ ] **Step 3: Commit**

```bash
git add supabase/apply_migrations.sh
git commit -m "feat(supabase): idempotent apply script + _ccrl_migrations tracking (#20)"
```

---

### Task 5: Drift-check script

**Files:**
- Create: `supabase/check_migrations.sh`

- [ ] **Step 1: Write the drift-check script**

Create `supabase/check_migrations.sh`:

```bash
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
```

- [ ] **Step 2: Static sanity check (no DB)**

```bash
chmod +x supabase/check_migrations.sh
bash -n supabase/check_migrations.sh && echo "syntax OK"
unset DATABASE_URL; ./supabase/check_migrations.sh; echo "exit=$?"
```
Expected: `syntax OK`, then the `set DATABASE_URL` message + non-zero exit.

- [ ] **Step 3: Commit**

```bash
git add supabase/check_migrations.sh
git commit -m "feat(supabase): local migration drift-check script (#20)"
```

---

### Task 6: README + CI lint wiring

**Files:**
- Create: `supabase/README.md`
- Modify: `.github/workflows/check.yml`

- [ ] **Step 1: Write `supabase/README.md`**

```markdown
# Supabase migrations

Plain numbered SQL migrations applied to the live Supabase project by a small
`psql` script. No Supabase CLI. Every migration is **idempotent**, so the whole
set re-runs to converge — this is also the fresh-project-recreate path.

## The idempotency rule (enforced by `lint_migrations.sh`)

Every statement must be safe to run twice:
- `create table/index` → `... if not exists`
- `alter table ... add column` → `... add column if not exists`
- `alter table ... drop column` → `... drop column if exists`
- `create policy "P" on T ...` → precede with `drop policy if exists "P" on T;`
- `alter publication powersync add table T` → wrap in a `do $$ ... if not exists
  (select 1 from pg_publication_tables ...) then execute '...'; end if; end $$;`

`./supabase/lint_migrations.sh` (no DB) fails the build if any migration breaks
this. It also runs in CI.

## DATABASE_URL

Use the **direct/session** connection string (NOT the pooler) — DDL +
`alter publication` need a direct session. Supabase → Project Settings →
Database → Connection string → URI (Session mode).

```bash
export DATABASE_URL='postgresql://postgres:<pwd>@db.<ref>.supabase.co:5432/postgres'
```

## Deploy

```bash
./supabase/apply_migrations.sh   # applies all migrations, records versions
./supabase/check_migrations.sh   # ✓ in sync, or lists drift
```

## Acceptance test (the real verification)

These migrations reference Supabase-only objects (`auth.users`, the `powersync`
publication), so they can't be run on a vanilla local Postgres. Verify against
the live (or a Supabase branch) DB:

1. `./supabase/apply_migrations.sh` — applies anything missing (e.g. 0009/0010).
2. Run it **again** — must complete with zero errors (all no-ops). This proves
   idempotency/convergence.
3. `./supabase/check_migrations.sh` — must print `✓ in sync`.
```

- [ ] **Step 2: Add a DB-free lint step to CI**

In `.github/workflows/check.yml`, after the `flutter test` step, add:

```yaml
      - name: Lint Supabase migrations (idempotency)
        run: ./supabase/lint_migrations.sh
```

- [ ] **Step 3: Verify CI step locally + commit**

```bash
./supabase/lint_migrations.sh && echo "lint passes"
git add supabase/README.md .github/workflows/check.yml
git commit -m "docs(supabase): README + CI idempotency-lint step (#20)"
```

---

## Self-Review

**Spec coverage:**
- Goal 1 (idempotent apply) → Task 4. ✓
- Goal 2 (local drift check) → Task 5. ✓
- Goal 3 (all migrations idempotent + fresh-recreate) → Tasks 2–3 + README. ✓
- Migration hygiene table (each transform) → Tasks 2–3 + lint (Task 1). ✓
- Tracking table `_ccrl_migrations` → Task 4 Step 1. ✓
- bash + psql, no CLI → Tasks 4/5. ✓
- README w/ DATABASE_URL direct, idempotency rule, twice-run acceptance → Task 6. ✓
- Testing limitation + twice-run as acceptance test → Task 6 README; lint is the automatable partial gate (Task 1). ✓
- Non-goal "no CI-enforced *drift*" respected — CI runs only the DB-free *lint*, not drift. ✓

**Placeholder scan:** none — every script + SQL transform is concrete.

**Consistency:** tracking table `public._ccrl_migrations(version, applied_at)` and the `version` = numeric filename prefix are identical across apply (writes), check (reads), and the lint (untouched). Script names `lint_migrations.sh` / `apply_migrations.sh` / `check_migrations.sh` consistent throughout.

**Note for the implementer:** the lint covers table/index/column/drop/publication reliably and policy via a per-file create-vs-drop count. Duplicate-policy or other edge regressions that slip past the lint are caught by the live twice-run acceptance test (README) — that run, not the lint, is the authoritative verification, and it needs the user's live `DATABASE_URL`.
```
