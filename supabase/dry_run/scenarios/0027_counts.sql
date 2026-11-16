-- One line per synced table: name and row count. Run as postgres with -At.
select 'dive_annotations ' || count(*) from public.dive_annotations union all
select 'cylinders ' || count(*) from public.cylinders union all
select 'oxygen_cells ' || count(*) from public.oxygen_cells union all
select 'scrubber_sessions ' || count(*) from public.scrubber_sessions union all
select 'pressure_mappings ' || count(*) from public.pressure_mappings union all
select 'dive_cylinders ' || count(*) from public.dive_cylinders union all
select 'dive_computers ' || count(*) from public.dive_computers union all
select 'dives ' || count(*) from public.dives union all
select 'dive_samples ' || count(*) from public.dive_samples union all
select 'dive_attachments ' || count(*) from public.dive_attachments union all
select 'dive_bailout_carry ' || count(*) from public.dive_bailout_carry union all
select 'dive_plans ' || count(*) from public.dive_plans union all
select 'dive_merge_links ' || count(*) from public.dive_merge_links union all
select 'gas_analyses ' || count(*) from public.gas_analyses union all
select 'user_acknowledgements ' || count(*) from public.user_acknowledgements union all
select 'open_blends ' || count(*) from public.open_blends
order by 1;
