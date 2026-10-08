-- Prune the pg_cron run log (issue #98).
--
-- 0008 schedules `reap-stale-replication-slots` every 15 minutes. Each run
-- appends a row to `cron.job_run_details`, which pg_cron never cleans up;
-- it was already 2.6 MB on a free-tier database. This migration deletes
-- rows older than 7 days once now, and schedules a daily job that does
-- the same so the table stays small.
--
-- Creates no table, so no grants are needed.

delete from cron.job_run_details
where end_time < now() - interval '7 days';

-- Idempotent, same pattern as 0008: cron.schedule errors if a job with
-- this name already exists, so drop it first.
select cron.unschedule('prune-cron-run-log')
where exists (
  select 1 from cron.job where jobname = 'prune-cron-run-log'
);
select cron.schedule(
  'prune-cron-run-log',
  '17 3 * * *',
  $$delete from cron.job_run_details where end_time < now() - interval '7 days'$$
);
