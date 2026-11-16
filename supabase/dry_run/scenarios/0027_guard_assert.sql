-- After the guard refused 0027, nothing of it may remain: every synced
-- table is still keyed by id alone, and the old single-column foreign keys
-- are still there. Run as postgres without --single-transaction.
do $$
declare bad text;
begin
  select string_agg(t.tablename || ' pk=' || coalesce(pk.cols::text, 'none'), ', ')
    into bad
  from pg_publication_tables t
  left join lateral (
    select array_agg(a.attname::text order by k.ord) cols
    from pg_index i
    cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
    join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
    where i.indrelid = format('public.%I', t.tablename)::regclass and i.indisprimary
  ) pk on true
  where t.pubname = 'powersync' and pk.cols is distinct from array['id'];
  if bad is not null then
    raise exception 'guard: 0027 was not rolled back, primary keys changed on: %', bad;
  end if;

  if (select count(*) from pg_constraint
      where contype = 'f' and cardinality(conkey) = 1
        and confrelid in ('public.dives'::regclass, 'public.cylinders'::regclass)) <> 4 then
    raise exception 'guard: the four single-column foreign keys into dives and cylinders are not all still there';
  end if;
  if exists (select 1 from pg_constraint
             where conname in ('dive_samples_owner_dive_fkey', 'dive_bailout_carry_owner_dive_fkey',
                               'dive_bailout_carry_owner_cylinder_fkey', 'dive_merge_links_owner_dive_fkey')) then
    raise exception 'guard: a composite foreign key from 0027 survived the rollback';
  end if;
end $$;
