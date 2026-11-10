-- Phase 3 cloud schema. Per-dive attachments — files (PDFs, images,
-- DOC/XLSX, etc.) hosted on Cloudflare R2, plus user-supplied URL links.
-- Metadata syncs through PowerSync; file bytes live in R2 and are
-- fetched on demand via signed URLs minted by the upload-signing
-- Worker. Mirrors the canonical sync-metadata pattern from
-- 0001_initial_schema.sql.
--
-- A single table with a `kind` discriminator (instead of two tables for
-- files and links) keeps the list-by-dive query, RLS policy, and sync
-- rule each at a single line. The CHECK constraint enforces that
-- file-only columns are populated for files and link-only columns are
-- populated for links.
--
-- `parent_kind` / `parent_id` are generic on purpose so the same
-- infrastructure can carry "dive certifications" (Phase 3 follow-up)
-- without a schema change. For v1 every row has `parent_kind = 'dive'`
-- and `parent_id` = the canonical dive id hash.
--
-- `storage_key` is the R2 object key — see the Cloudflare Worker
-- (worker/src/index.ts) for the layout: attachments/{owner_id}/
-- {dive_id}/{uuid}.{ext}. The owner_id prefix lets future
-- bucket-policy or cleanup tooling scope per-user with a single match.
--
-- `upload_state` (0 pending, 1 uploaded, 2 failed, 3 purged) is the
-- only column the client mutates after the row exists; everything else
-- is write-once-on-create + soft-delete. There is no automatic upload
-- retry: a `failed` row is retried by the user from the app. State 3
-- (added by #196) marks a soft-deleted row whose R2 object the app has
-- deleted, 24 hours after `deleted_at`.

create table if not exists dive_attachments (
  id text primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,

  parent_kind text not null default 'dive'
    check (parent_kind in ('dive', 'certification')),
  parent_id text not null,
  kind text not null check (kind in ('file', 'link')),

  -- shared, optional
  title text,
  description text,
  display_order integer not null default 0,

  -- file-only (null when kind = 'link')
  storage_key text,
  mime_type text,
  size_bytes bigint,
  original_filename text,
  checksum_sha256 text,
  upload_state integer not null default 0,
  upload_attempts integer not null default 0,

  -- link-only (null when kind = 'file')
  url text,

  -- sync metadata
  created_at bigint not null,
  updated_at bigint not null,
  deleted_at bigint,
  version integer not null default 1,
  sync_status integer not null default 0,

  constraint dive_attachments_kind_columns check (
    (kind = 'file'
       and storage_key is not null
       and mime_type is not null
       and url is null)
    or
    (kind = 'link'
       and url is not null
       and storage_key is null)
  )
);

alter table dive_attachments enable row level security;
drop policy if exists "owner_full_access" on dive_attachments;
create policy "owner_full_access"
  on dive_attachments for all
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

-- RLS query path index (mirrors 0002_owner_id_indexes.sql).
create index if not exists dive_attachments_owner_id_idx
  on dive_attachments (owner_id);

-- The "list everything attached to this dive" query.
create index if not exists dive_attachments_parent_idx
  on dive_attachments (parent_kind, parent_id);

-- Used by the orphan-cleanup tooling; partial because link rows have
-- null storage_key and we never look them up by it.
create index if not exists dive_attachments_storage_key_idx
  on dive_attachments (storage_key)
  where storage_key is not null;

-- PowerSync publication ------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'powersync' and schemaname = 'public' and tablename = 'dive_attachments') then
    execute 'alter publication powersync add table public.dive_attachments';
  end if;
end $$;
