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

## 4. Apply the sync rules

Paste the contents of `powersync-sync-rules.yaml` into the
PowerSync instance under **Sync Rules**. One bucket per
authenticated user, scoped on `owner_id`.

## 5. Point the app at the instance

Copy the PowerSync URL (looks like
`https://xxxxx.powersync.journeyapps.com`) and pass it to the app:

```sh
flutter run --dart-define=POWERSYNC_ENDPOINT=https://xxxxx.powersync.journeyapps.com
```

For release builds, set it on `flutter build`. The constant is read by
`lib/sync/cloud/cloud_config.dart`.
