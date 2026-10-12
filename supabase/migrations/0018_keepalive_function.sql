-- Keep-alive target for the Cloudflare Worker (issue #98).
--
-- The Worker's daily keep-alive (worker/src/keepalive.ts) holds only the
-- public anon key. 0016 deliberately grants the anon role nothing on any
-- table, so a read of `dives` is refused with 42501 / HTTP 401. This adds
-- the one thing anon may do: call a function that touches no data and
-- returns 1. That is a real, successful database request, which is what
-- keeps a free-tier project from being paused.
--
-- Temporary, like the keep-alive itself: drop this function when the
-- project moves to a paid plan and the Worker's cron trigger is removed.
--
-- Creates no table, so no table grants are needed.

create or replace function public.keepalive()
returns integer
language sql
stable
set search_path = ''
as $$
  select 1
$$;

revoke all on function public.keepalive() from public;
grant execute on function public.keepalive() to anon, authenticated, service_role;
