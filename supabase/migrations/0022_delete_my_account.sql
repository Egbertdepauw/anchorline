-- In-app account deletion (App Store guideline 5.1.1(v), Google Play
-- account-deletion policy). Spec: docs/superpowers/specs/
-- 2026-11-08-account-deletion-design.md, section 6.1.
--
-- delete_my_account() deletes the calling user's row in auth.users. Every
-- owner_id foreign key in the schema is `on delete cascade`, so that one
-- delete removes the account and all of its data in a single transaction:
-- everything is removed or nothing is. PowerSync replicates the deletes.
--
-- `security definer` is needed because the `authenticated` role has no
-- rights on auth.users. It is safe because the body can only ever touch
-- the caller's own row (auth.uid()), refuses an unauthenticated call, pins
-- search_path, and execute is revoked from public and anon.
--
-- statement_timeout is raised from the authenticated default (8 s) so a
-- large log can finish; PostgREST applies it to RPC calls and Supabase
-- caps client queries at 60 s.
--
-- Nothing is created in the auth schema (Supabase forbids that); deleting
-- rows from auth.users through a function in public is not restricted.
--
-- Temporary exception to the 2026-11-02 backend decision (account deletion
-- belongs in the Dart service, spec section 4). When that service exists,
-- deletion moves there and this function can be dropped.
--
-- Creates no table, so no table grants are needed.

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
set statement_timeout = '50s'
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not signed in' using errcode = '28000';
  end if;
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
