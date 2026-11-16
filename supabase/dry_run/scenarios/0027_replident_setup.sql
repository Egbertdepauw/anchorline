-- State for the 0027 replica identity guard test: one synced table uses its
-- old id-only primary key index as REPLICA IDENTITY. Dropping that index would
-- leave the table at NOTHING. Run as postgres, before 0027.
alter table public.dives replica identity using index dives_pkey;
