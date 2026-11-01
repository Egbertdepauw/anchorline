-- Cylinder gas labels (issue #114): what the diver wanted the cylinder to
-- hold, and what the gas is for, saved with each analysis so a reprint looks
-- the same later.
--
-- target_o2_percent / target_he_percent: the DESIRED mix as whole percents
-- (e.g. 21 / 35 for Tx21/35). Whole numbers rather than a name, so the naming
-- rule stays in gas_naming.dart and the 50 % ppO2 rule can read the O2. Both
-- are nullable: null target O2 means no desired mix was set, and a null target
-- He with a target O2 counts as 0 % He. The measured o2_percent / he_percent
-- are never touched; the label and the match grade compare against them.
--
-- gas_role: 'diluent' or 'bailout' ('bailout' covers bailout, deco, stage and
-- OC). Nullable: null means bailout/deco, so rows saved before this migration
-- print the bailout/deco label. Stored on the analysis, not looked up from the
-- cylinder, so changing the cylinder's role in Equipment later can't change an
-- old label. The app reads any value other than 'diluent' as bailout/deco.
--
-- The table already exists, so no grants and no publication change here
-- (see 0019_gas_analyses.sql). Deploy this BEFORE shipping a build that writes
-- these columns: the upload connector sends the whole row, so Supabase rejects
-- analysis uploads from a newer build until the columns exist.
ALTER TABLE gas_analyses ADD COLUMN IF NOT EXISTS target_o2_percent integer;
ALTER TABLE gas_analyses ADD COLUMN IF NOT EXISTS target_he_percent integer;
ALTER TABLE gas_analyses ADD COLUMN IF NOT EXISTS gas_role text;

NOTIFY pgrst, 'reload schema';
