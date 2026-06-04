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
- `create/alter publication ... ` → wrap in a `do $$ ... if not exists
  (select 1 from pg_publication[_tables] ...) then execute '...'; end if; end $$;`

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
