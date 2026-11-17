-- libdivecomputer phase 2. Adds dives.dc_fingerprint, the lower-case hex of the
-- libdivecomputer fingerprint of a dive.
--
-- Every libdivecomputer dive has dc_dive_number 0, so the same-dive matcher
-- cannot tell apart two dives from one computer that start less than 60 s
-- apart (a 30-second "dive" when the diver jumps in, then the real dive). With
-- the fingerprint, a stored libdivecomputer dive matches only the same
-- fingerprint. The Subsurface writer needs it too, on devices without the raw
-- blob and on the server, because Subsurface's diveid is the SHA-1 of it.
--
-- Nullable and not backfilled: it is set only on libdivecomputer dives
-- (dc_family is set), and no such dive exists yet. Shearwater downloads and
-- Subsurface copies keep NULL.

ALTER TABLE public.dives ADD COLUMN IF NOT EXISTS dc_fingerprint text;

-- Explicit Data API grant (issue #76), restated for the table this touches.
grant select, insert, update, delete on table public.dives to authenticated, service_role;

NOTIFY pgrst, 'reload schema';
