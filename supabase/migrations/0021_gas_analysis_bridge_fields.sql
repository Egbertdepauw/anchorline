-- Log on OK (issue #113): analyses saved by the SOLO bridge when the diver
-- presses OK on the analyzer, and the sign-off flag that marks entries that
-- still need the diver's attention.
--
-- needs_signoff: 0/1 (integer, like the other flags on this table), NOT NULL
-- DEFAULT 0. 1 means the entry isn't complete yet (no analysed by or desired
-- mix, an unstable reading, a mismatch, a failed print, a late record) and
-- waits in the analysis log as "needs sign-off". Signing off in the log, or
-- a successful print, sets it back to 0. Rows saved before this migration
-- read as 0.
--
-- capture_source: how the entry got into the log. 'bridge_ok' for a capture
-- the bridge made on the OK press; null for an analysis saved from the
-- analyzer screen. The app reads any other value as a screen save.
--
-- bridge_record_id: the bridge's own id for the capture, '<bridge>/<rid>'
-- (e.g. 'a1b2c3d4e5f6/1a2b3c4d-7'), for tracing. Null for screen saves. The
-- row id itself is derived from it, so a capture the bridge delivers twice
-- (a lost ACK, a reconnect) lands as one row.
--
-- analysed_for: who the gas is for (a name, free text). Nullable. Separate
-- from analysed_by, which is who ran the analysis.
--
-- The table already exists, so no grants and no publication change here
-- (see 0019_gas_analyses.sql). Deploy this BEFORE shipping a build that writes
-- these columns: the upload connector sends the whole row, so Supabase rejects
-- analysis uploads from a newer build until the columns exist.
ALTER TABLE gas_analyses ADD COLUMN IF NOT EXISTS needs_signoff integer NOT NULL DEFAULT 0;
ALTER TABLE gas_analyses ADD COLUMN IF NOT EXISTS capture_source text;
ALTER TABLE gas_analyses ADD COLUMN IF NOT EXISTS bridge_record_id text;
ALTER TABLE gas_analyses ADD COLUMN IF NOT EXISTS analysed_for text;

NOTIFY pgrst, 'reload schema';
