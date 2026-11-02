---
name: sync-recovery
description: Recovery procedures for live sync incidents - PowerSync replication slot stalling Supabase Postgres, Reset Everything leaving rows, stale Subsurface bootstrap clone, owner_id NULL after importing while signed out, Subsurface Cloud branch corruption. Use when sync goes red, uploads fail with RLS errors, or imported/synced data looks wrong.
---

# Sync recovery procedures


These are the recovery paths for issues we've actually hit on the live deployment. Follow them in order — most are fast and safe, the last is destructive.

### PowerSync replication slot stalls Postgres

Symptom: app sync indicator goes red. Supabase dashboard shows Database/PostgREST/Storage all "Unhealthy". PowerSync's dashboard issues panel reports `connect ECONNREFUSED ...:5432`, `No replicated commit in more than NNNNNs`, `postgres query failed`. Restarting the project from the dashboard brings it back up still unhealthy.

What's happening: PowerSync's connection died at some point; its logical-replication slot keeps WAL pinned in Postgres; on the NANO compute tier the WAL partition fills up; Postgres stops accepting connections. A restart can't recover because the slot still pins WAL on startup.

Recovery (try in order):

1. **Drop the slot via SQL Editor / Management API SQL endpoint** while Postgres is still partially responsive:
   ```sql
   SELECT pg_terminate_backend(active_pid)
   FROM pg_replication_slots WHERE active_pid IS NOT NULL;
   SELECT pg_drop_replication_slot(slot_name) FROM pg_replication_slots;
   ```
2. If SQL paths all return `ECONNREFUSED`, the project is fully wedged. Best lever left: **`POST /v1/projects/{ref}/pause` then `POST /v1/projects/{ref}/restore` via the Management API** (the dashboard's pause button silently no-ops once Postgres is dead, but the API call sometimes still goes through).
3. If pause/restore also fails, **recreate the project from scratch** (`POST /v1/projects` with same org_slug + region). Apply migrations from `supabase/migrations/` (the bundle script in `/tmp/ccrl_fresh_setup.sql` is the consolidated form). Patch the new project ref + anon key into `lib/sync/cloud/cloud_config.dart` and `worker/wrangler.toml`. Repoint PowerSync's source-DB connection in PowerSync's dashboard. Redeploy worker (`cd worker && npx wrangler deploy`). User does a fresh import on the device.

Long-term mitigation: move `dive_samples` out of replication (it's the heaviest sync table by an order of magnitude — its WAL volume is what makes the NANO tier vulnerable), or upgrade tier so the WAL partition is bigger.

### "Reset Everything" doesn't fully clear local state

`Settings → Reset everything` calls `psDb.disconnectAndClear()` which is supposed to wipe the local PowerSync SQLite. **In practice it leaves rows behind** — confirmed 2026-05-10. Subsequent bootstrap-imports then dedup-skip those stale rows by `(dcSerial, startTime)` and never re-parse, so old broken data persists.

If a re-import doesn't fix the data, the cleanest workaround is to **delete the local PowerSync SQLite file directly**:
```bash
rm /Users/<you>/Library/Containers/com.example.ccrlogger/Data/Documents/powersync.db*
```
then restart the app and re-import. The wildcard catches `.db`, `.db-wal`, and `.db-shm`.

Long-term fix: rework `Settings → Reset everything` to also `rm` the SQLite file as a fallback, or file an upstream PowerSync bug.

### Bootstrap clone goes stale relative to user's main repo

CCRLog keeps an internal git clone of the Subsurface repo at `~/Library/Containers/com.example.ccrlogger/Data/Documents/subsurface_clone/<email>-bootstrap/`. Bootstrap-import reads from **this clone**, not from any external git checkout the user might also have.

If the user's Subsurface app re-uploaded older dives with newer DC recordings (e.g. switching primary DC), the cloud branch updates — but **CCRLog's clone is never refreshed across bootstrap runs**. Result: bootstrap re-parses stale data, producing wrong PPO2/setpoint traces because the older Subsurface format uses sparse `dc_supplied_ppo2=` and frequent rounded `po2=` tokens, whereas the modern Petrel-3 format inverts that ratio.

Recovery: delete the clone alongside the local DB:
```bash
rm -rf ~/Library/Containers/com.example.ccrlogger/Data/Documents/subsurface_clone
rm /Users/<you>/Library/Containers/com.example.ccrlogger/Data/Documents/powersync.db*
```
then restart and re-import — bootstrap will re-clone fresh.

Long-term fix: bootstrap should `git fetch && git reset --hard origin/<branch>` before reading, or compare commit hashes and re-clone on mismatch.

### Sign in BEFORE bootstrap-import, not after

Sample data flowing through `dao.importDive()` stamps `owner_id` from the current Supabase session at write time. If the user is **not signed in** when bootstrap runs, every `dives` and `dive_samples` row gets `owner_id = NULL`. Sync indicator goes green because there's no auth needed locally — but the moment the user signs in, PowerSync's CRUD upload fails every row with `new row violates row-level security policy for table "dives"`.

The existing `OwnerIdBackfiller` (run on first sign-in) **omits `dives` and `dive_samples`** — it only stamps the seven smaller equipment/annotation tables. So a sign-in after a not-signed-in import doesn't fix it; the only recovery today is to wipe local state and re-import while signed in.

Long-term fix: extend `OwnerIdBackfiller` with SQL `UPDATE` paths that stamp `owner_id = $userId WHERE owner_id IS NULL` against the existing PowerSync local rows for `dives` and `dive_samples`. The current backfiller does Drift→PowerSync copies; this needs to be an in-place PowerSync update instead.

### Subsurface-Cloud branch corruption from CCRLog write-direction sync

Historical incident (2026-05-08): an early version of the CCRLog → Subsurface git write-direction sync emitted samples in the older Subsurface format (sparse `dc_supplied_ppo2=`, frequent `po2=`) and force-pushed a commit titled "CCRLog sync — N dives" to Subsurface Cloud, **overwriting the user's authoritative recordings** for those dives. The user's main repo at `~/Dev/CCRLog/ss_git/...` retained the correct working-tree content because it hadn't fetched yet, but the cloud branch held the corrupt commit.

A safety hold is currently in place in `sync_orchestrator.dart` that throws unconditionally to prevent the write-direction code from running until the planner is rewritten. **Do not remove that hold without first**:

1. Making the serializer emit `dc_supplied_ppo2=` per-sample (current code only emits `po2=` based step values, which is what produced the broken output).
2. Adding conflict resolution: when CCRLog's planned write would change a Divecomputer file in a way that loses data Subsurface previously recorded, **abort that per-dive write** rather than overwrite.

If a user reports their Subsurface Cloud is corrupted again: have them force-push their main repo's HEAD over the cloud branch (`git push --force origin HEAD:<branch>`), reset Subsurface app's local cache (so it doesn't re-push the bad commit), then in CCRLog `rm -rf subsurface_clone` and re-bootstrap.
