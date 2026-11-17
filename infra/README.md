# Cloud sync setup

These files are applied through the Supabase and PowerSync dashboards.
They're not imported by the Dart code.

## 1. Apply the Postgres schema

Open the Supabase dashboard for the project and go to **SQL Editor**.
Paste the contents of `../supabase/migrations/0001_initial_schema.sql`
and run it. This creates the seven sync-eligible tables with
row-level security and the `powersync` publication.

## 2. Provision a PowerSync instance

Sign up at <https://www.powersync.com/> and create a new instance.
Connect it to the Supabase Postgres using the connection string from
**Project Settings → Database → Connection string**. Pick the
"transaction" pooler — PowerSync needs a direct connection.

## 3. Wire up authentication

In the Supabase dashboard, copy the JWKS URL from **Project Settings
→ Auth → JWT Settings**. Paste it into the PowerSync instance under
**Authentication → JWKS URL**. PowerSync will validate the JWTs that
the app gets from Supabase auth.

## 4. Apply the Sync Streams

Paste the contents of `powersync-sync-streams.yaml` into the PowerSync
instance's sync configuration and deploy it. It is Sync Streams
(`config: edition: 3`): two auto-subscribed streams. `user_data` has one
query per table, scoped on `owner_id = auth.user_id()`; `dives`,
`dive_samples`, `dive_computers` and `dive_bailout_carry` also carry
`AND dc_family IS NULL` there. `libdc_dives` carries the rows with
`dc_family` set, only to builds that connect with `dc_engines >= 2`
(`lib/sync/cloud/sync_params.dart`).

The app needs no subscribe call: `auto_subscribe: true` makes every client
sync the stream on connect. That needs the Dart SDK at 1.16.0 or later;
the app has been on `powersync` 2.x since it first used PowerSync.

### Switching an instance from Sync Rules to Sync Streams (#126)

Sync Rules (`bucket_definitions:`) are deprecated. PowerSync removes them in
the Service major version of 15 September 2027, and from 15 December 2027
they can no longer be deployed. Switching:

0. Paste the file into the dashboard and run **Validate** before
   deploying. Compare it with what the dashboard's "Migrate to Sync
   Streams" produces from the current Sync Rules: the same tables, each
   scoped on `owner_id`. Edition 3 and the `queries:` shape were not checked
   against a live Service when this file was written.
1. Before deploying, let every device you use finish syncing, so no
   changes are waiting to upload. PowerSync's docs don't say what happens
   to a client's pending upload queue during the switch, so don't test
   that with real data. To check a device: make no edits for a minute, and
   Settings → Sync must show synced (green), not uploading. The upload
   queue (`ps_crud`) is then empty; the sync-recovery skill
   (`.claude/skills/sync-recovery`) shows how to inspect it if in doubt.
2. Deploy the file. The Service reprocesses the data in the background
   while the old config keeps serving clients, then switches over without
   downtime.
3. After the switch, **every client does a one-time full re-sync**,
   including all dive samples. Expect a long first sync on each device, and
   more download traffic than usual for a day.
4. Check one device: sync goes green, the dive count matches, and an edit
   made after the switch reaches a second device.

Deploy checklist for the `libdc_dives` gate (libdivecomputer phase 1), in
this order:

1. Migration 0026 (PR 1, the `dc_family` columns) is live first, before
   anything else.
2. Paste the file into the dashboard editor and run **Validate**: no errors
   or warnings on the `libdc_dives` queries. The Streams docs show
   `connection.parameter()` compared with a column, not with a constant.
3. Let every device finish syncing first (see the switch steps above),
   then deploy. The switch from Sync Rules (#208) is already live, so this
   is a config change of its own: expect one more full re-sync per device.
4. Fake-row check. In the SQL editor insert a `dives` row for your account
   with `dc_family = 999`. It must **not** appear on an installed store
   build (it sends no params; this is the only live test that old builds are
   excluded) and **not** on a phase 1 build (`dc_engines: 1`): a build from
   before the commit that set `kSyncConnectionParams` to `{'dc_engines': 2}`
   ("skip other brands in the Subsurface writer"), or a store build that has
   phase 1 but not that commit. A build of the current branch sends
   `{'dc_engines': 2}`, so it can't be used for that leg. The row **must**
   appear on a build of the current branch. Then delete the row in SQL and
   check that it disappears on that build. While the row exists, don't open
   the fake dive on that build. A Subsurface push from it leaves the row out
   (another brand, not on Subsurface Cloud); a phase 1 build with the
   parameter changed by hand would write it as a Shearwater dive, so don't
   push from one.
5. Sync goes green and the dive count matches on one device.
6. This must be live before any phase-2 build exists.

If Validate rejects `connection.parameter('dc_engines') >= 2`, the fallback
is `libdc_dives` with `auto_subscribe: false` and no `connection.parameter`
clauses; phase 2 then subscribes explicitly. It is a repo change: this file
plus `test/sync/cloud/sync_streams_config_test.dart`. Never make it as a
dashboard-only edit.

Edition 3 also turns on PowerSync's edition 2 fixes: ISO 8601 timestamps
and custom Postgres type handling. Neither changes our data. The synced
tables store time as `bigint` epoch values, not `timestamp`/`timestamptz`,
and use no custom types (only `uuid`, `jsonb`, `text`, `integer`, `bigint`
and `double precision`). The only `timestamptz` and `boolean` columns are in
tables PowerSync doesn't sync (`usage_events`, the sync health checks).

## 5. Point the app at the instance

Copy the PowerSync URL (looks like
`https://xxxxx.powersync.journeyapps.com`) and pass it to the app:

```sh
flutter run --dart-define=POWERSYNC_ENDPOINT=https://xxxxx.powersync.journeyapps.com
```

For release builds, set it on `flutter build`. The constant is read by
`lib/sync/cloud/cloud_config.dart`.
