# Supabase migration deploy + drift detection

**Date:** 2026-06-03
**Status:** Approved, pending implementation
**Issue:** #20
**Area:** `supabase/` (migrations + new scripts), `docs/`

## Problem

There is no scripted path from `supabase/migrations/*.sql` to the live Supabase
database. Migrations are applied ad-hoc via the Dashboard SQL Editor — or
forgotten. Migration `0009_dive_annotation_divemaster` was in the repo but never
applied to live, so a beta user (Danny) hit
`PostgrestException(... 'divemaster' column ... not found ... PGRST204)` on 69
queued `dive_annotations` PUTs. Missing-schema bugs masquerade as sync bugs (#2).

Compounding it: some migrations aren't idempotent —
- `0010_display_deco_algorithm` is a bare `ADD COLUMN` (re-run → "column exists").
- `0011_dive_bailout_carry` does `DROP COLUMN` + `CREATE TABLE` + `ALTER
  PUBLICATION ... ADD TABLE` (re-run errors; a half-applied state is stuck).

And we have no way to know which migrations are live without manual SQL.

## Goals

1. A repeatable, idempotent way to apply `supabase/migrations/*.sql` to a target
   database from a connection string.
2. A local drift check that reports which migrations are in the repo but not yet
   applied to the live DB.
3. All migrations idempotent, so the full set can be re-run to converge — which
   doubles as the canonical fresh-project-recreate path (the disaster recovery in
   CLAUDE.md, replacing the ad-hoc `/tmp/ccrl_fresh_setup.sql`).

## Non-goals

- **Adopting the Supabase CLI** — rejected. It would require renaming all 14
  migrations to its timestamp format and reconciling an empty remote migration
  history. Keeps the numbered `0001..NNNN` files and stays dependency-light.
- **CI-enforced drift detection** — rejected for now. It would put a DB
  credential into CI, which `check.yml` deliberately avoids. Drift detection is a
  local script; revisit CI enforcement later if solo-dev discipline proves
  insufficient.
- **Automated CI testing of the migrations** — not feasible (see Testing).
- **PowerSync-managed schema** — PowerSync replicates rows, not schema. Out of
  scope.

## Design

### Tooling: bash + `psql`

`psql` is the natural SQL applier (`psql "$DATABASE_URL" -f file.sql`) and adds no
package to `pubspec.yaml`. Two scripts under `supabase/`, both reading the target
DB from the `DATABASE_URL` env var (the Supabase **direct** connection string,
not the pooler — DDL + publication changes need a direct session).

### 1. Migration hygiene — make all 14 idempotent

Rewrite each migration so re-running the whole set converges with zero errors,
preserving numeric run order (fresh-create ordering is unchanged):

| Pattern | Idempotent form |
|---|---|
| `ADD COLUMN x` | `ADD COLUMN IF NOT EXISTS x` |
| `CREATE TABLE t (...)` | `CREATE TABLE IF NOT EXISTS t (...)` |
| `CREATE INDEX i ...` | `CREATE INDEX IF NOT EXISTS i ...` |
| `ALTER TABLE t DROP COLUMN c` | `ALTER TABLE t DROP COLUMN IF EXISTS c` |
| `CREATE POLICY p ...` | `DROP POLICY IF EXISTS p ON t;` then `CREATE POLICY p ...` |
| `ALTER PUBLICATION powersync ADD TABLE t` | guarded in a `DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='powersync' AND schemaname='public' AND tablename='t') THEN EXECUTE 'ALTER PUBLICATION powersync ADD TABLE public.t'; END IF; END $$;` |

Keep the trailing `NOTIFY pgrst, 'reload schema';` lines. `ENABLE ROW LEVEL
SECURITY` is already idempotent (no-op if already enabled). `COMMENT ON` is
idempotent. `0011`'s `DROP COLUMN gas_mix` becomes `DROP COLUMN IF EXISTS gas_mix`
(no-op where already dropped).

**Rule for all future migrations:** every statement must be idempotent. Documented
in the README.

### 2. Tracking table

```sql
CREATE TABLE IF NOT EXISTS public._ccrl_migrations (
  version    text PRIMARY KEY,        -- the 0001..NNNN filename prefix
  applied_at timestamptz NOT NULL DEFAULT now()
);
```

Our own table, keyed by the numeric filename prefix. Not the Supabase CLI's
`supabase_migrations.schema_migrations` (we're not adopting the CLI).

### 3. Apply script — `supabase/apply_migrations.sh`

```
DATABASE_URL=postgres://... ./supabase/apply_migrations.sh
```

- `set -euo pipefail`; require `DATABASE_URL`.
- Ensure `public._ccrl_migrations` exists.
- For each `supabase/migrations/NNNN_*.sql` in sorted order:
  - Apply it inside a single transaction with `psql -v ON_ERROR_STOP=1 --single-transaction -f <file>`, followed (same invocation) by an
    `INSERT INTO public._ccrl_migrations(version) VALUES ('NNNN') ON CONFLICT DO NOTHING;`
  - Because migrations are idempotent, every file is applied on every run; the
    tracking table records the version. A failure rolls back that migration and
    stops the script (nothing half-applied).
- Print each version applied + a final summary.

It always runs the full set (the convergence guarantee), not just un-tracked ones.

### 4. Drift check — `supabase/check_migrations.sh`

```
DATABASE_URL=postgres://... ./supabase/check_migrations.sh
```

- Collect repo versions from `supabase/migrations/*.sql` filenames.
- Query `SELECT version FROM public._ccrl_migrations` (empty set if the table
  doesn't exist yet → treat all as un-applied).
- Report: **drift** = versions in files but not in the table (deploy needed);
  **orphans** = versions in the table with no file (unexpected). Exit non-zero if
  either set is non-empty; exit 0 + "in sync" otherwise.

### 5. Docs — `supabase/README.md`

How to obtain the direct `DATABASE_URL` (Supabase → Project Settings → Database →
Connection string → URI, direct/session, not the pooler), run apply + check, the
idempotency rule for future migrations, and the fresh-recreate procedure.

## Error handling

- Each migration applies in its own transaction (`--single-transaction` +
  `ON_ERROR_STOP=1`): a failure rolls the migration back and aborts the run, never
  leaving a half-applied migration.
- Guarded DDL means a database in any partial prior state converges.
- Missing `DATABASE_URL` or `psql` → the script exits with a clear message.

## Testing — limitation, stated honestly

These migrations reference Supabase-only objects (`auth.users`, the `powersync`
publication, `wal_level=logical`). A vanilla local Postgres can't fully run them,
so automated unit/CI testing isn't feasible without replicating the Supabase
environment. Verification is therefore:

1. **Idempotency review** of every rewritten migration against the table above.
2. **Run `apply_migrations.sh` twice against the live DB** (you — I can't touch
   live): the first run applies the missing migrations (0009/0010); the second
   run must be all no-ops with zero errors, proving convergence. This is safe
   precisely because the migrations are idempotent.
3. **Run `check_migrations.sh`** after applying: must report "in sync".

The README documents this twice-run check as the acceptance test.

## What requires the user (live-DB access I don't have)

- Running `apply_migrations.sh` against live Supabase with the real
  `DATABASE_URL` — this is the remediation that closes Danny's PGRST204.
- The twice-run idempotency verification + `check_migrations.sh` confirmation.

## Out of scope / follow-ups

- CI-enforced drift gate (needs a DB secret in Actions) — revisit if needed.
- A re-drive of users whose queues already failed on the missing column (that's
  the #2 quarantine / manual drain path, tracked separately).
