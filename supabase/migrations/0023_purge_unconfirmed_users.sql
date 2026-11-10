-- Purge sign-ups that never confirmed their email (issue #189).
--
-- Since PR #190 a new account must confirm its email before it gets a
-- session. Anyone can still call the sign-up API, though, and every call
-- leaves an auth.users row behind. This migration adds a nightly pg_cron
-- job that deletes accounts whose email is still unconfirmed 7 days after
-- sign-up. The confirmation code (and the old email link) expires after 1
-- hour, so these accounts can never be confirmed; the 7 days only leave
-- time to look into a sign-up complaint first.
--
-- `email is not null` keeps the job to email sign-ups. Anonymous and phone
-- users have no email, and the app uses neither, but they must not be
-- swept up if that ever changes.
--
-- An unconfirmed user never had a session, so it cannot own rows. Every
-- owner_id foreign key is `on delete cascade` anyway. The three NO ACTION
-- foreign keys into a user's data (dive_bailout_carry.dive_id and
-- .cylinder_id, dive_merge_links.id) are cleared first, exactly as
-- public.delete_my_account() in 0022 does, so the auth delete can never
-- fail on them. The audit-log entries that hold the email and IP address
-- are deleted too, guarded the same way as in 0022.
--
-- Not `security definer`: the cron job runs as the role that scheduled it
-- (postgres, which applies migrations), which already has the rights.
-- Execute is revoked from everyone else, so the Data API cannot call it.
--
-- Creates no table, so no table grants are needed.

create or replace function public.purge_unconfirmed_users()
returns integer
language plpgsql
set search_path = ''
as $$
declare
  doomed uuid[];
begin
  -- FOR UPDATE makes a confirmation racing with this run wait, and then
  -- find the user gone, instead of confirming a user being deleted.
  select coalesce(array_agg(id), '{}') into doomed
  from (
    select id
    from auth.users
    where email_confirmed_at is null
      and email is not null
      and created_at < now() - interval '7 days'
    for update
  ) s;

  if cardinality(doomed) = 0 then
    return 0;
  end if;

  delete from public.dive_bailout_carry
  where dive_id in (select id from public.dives where owner_id = any(doomed))
     or cylinder_id in (select id from public.cylinders where owner_id = any(doomed));
  delete from public.dive_merge_links
  where id in (select id from public.dives where owner_id = any(doomed));

  begin
    delete from auth.audit_log_entries
    where payload->>'actor_id' in (select u::text from unnest(doomed) u);
  exception when insufficient_privilege or undefined_table then
    null;
  end;

  delete from auth.users where id = any(doomed);
  return cardinality(doomed);
end;
$$;

revoke all on function public.purge_unconfirmed_users() from public, anon, authenticated, service_role;

-- Idempotent, same pattern as 0008 and 0017: cron.schedule errors if a job
-- with this name already exists, so drop it first.
select cron.unschedule('purge-unconfirmed-users')
where exists (
  select 1 from cron.job where jobname = 'purge-unconfirmed-users'
);
select cron.schedule(
  'purge-unconfirmed-users',
  '43 3 * * *',
  $$select public.purge_unconfirmed_users()$$
);
