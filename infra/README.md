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

Paste the contents of `powersync-sync-rules.yaml` into the PowerSync
instance's sync configuration and deploy it. It is Sync Streams
(`config: edition: 3`): one auto-subscribed stream, `user_data`, with one
query per table, scoped on `owner_id = auth.user_id()`. The file name is
kept from the Sync Rules days so the many references to it stay valid.

The app needs no subscribe call: `auto_subscribe: true` makes every client
sync the stream on connect. That needs the Dart SDK at 1.16.0 or later;
the app has been on `powersync` 2.x since it first used PowerSync.

### Switching an instance from Sync Rules to Sync Streams (#126)

Sync Rules (`bucket_definitions:`) are deprecated. PowerSync removes them in
the Service major version of 15 September 2027, and from 15 December 2027
they can no longer be deployed. Switching:

1. Before deploying, let every device you use finish syncing, so no
   changes are waiting to upload. PowerSync's docs don't say what happens
   to a client's pending upload queue during the switch, so don't test
   that with real data.
2. Deploy the file. The Service reprocesses the data in the background
   while the old config keeps serving clients, then switches over without
   downtime.
3. After the switch, **every client does a one-time full re-sync**,
   including all dive samples. Expect a long first sync on each device, and
   more download traffic than usual for a day.
4. Check one device: sync goes green, the dive count matches, and an edit
   made after the switch reaches a second device.

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
