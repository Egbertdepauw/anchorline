create table cron.job (
  jobid bigserial primary key,
  jobname text unique,
  schedule text,
  command text
);

create table cron.job_run_details (
  runid bigserial primary key,
  jobid bigint,
  end_time timestamptz
);

create function cron.schedule(job_name text, schedule text, command text)
returns bigint language sql as $$
  insert into cron.job (jobname, schedule, command)
  values (job_name, schedule, command)
  on conflict (jobname) do update
    set schedule = excluded.schedule, command = excluded.command
  returning jobid
$$;

create function cron.unschedule(job_name text)
returns boolean language plpgsql as $$
begin
  delete from cron.job where jobname = job_name;
  return found;
end $$;
