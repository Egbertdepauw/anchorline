# Subsurface Cloud sync as a backend service — design

Status: approved by Egbert on 2026-11-02. No product code yet.
Supersedes the in-app design in `docs/subsurface_git_library.md` and the
"Subsurface git sync architecture" memory note of 2026-05-08.

## 1. Intent

Move Anchorline's Subsurface Cloud sync out of the app and into a
backend service that Anchorline runs. The app stops linking libgit2
(`git2dart`) on every platform; the server does all git work with the
system `git` binary against the user's repo at
`https://ssrf-cloud-<region>.subsurface-divelog.org/git/<email>`.

Why now:

- **iPhone has no Subsurface sync at all.** `git2dart_binaries` ships no
  iOS dylibs, so `SubsurfaceRepo.isPlatformSupported` is false on iOS.
  iOS is a launch platform.
- **Native packaging has cost weeks.** The macOS dylib needs macOS ≥ 26,
  ships a static OpenSSL with no CA store (`ssl_certs.dart`), and the
  Windows DLL bundling broke the Windows build outright for months
  (issue #74). Every binaries bump is a risk.
- **A stale per-device clone produced wrong data.** The bootstrap clone
  under `subsurface_clone/<email>-bootstrap/` is never refreshed, so a
  re-run re-parses old history (CLAUDE.md, "Bootstrap clone goes stale").
- **The 2026-05-08 incident.** An early write direction force-pushed over
  the user's recordings. Safety rules are easier to enforce, audit and
  fix in one server than in N app builds in the field.
- **Automatic sync.** Egbert wants Subsurface kept in step without
  pressing a button. Only a server can do that unattended.

## 2. Goals, non-goals, anti-goals

Goals:

1. Subsurface sync works on every platform Anchorline ships on,
   including iOS, with identical behaviour.
2. Ongoing sync is automatic for paying users: no button, "last synced"
   visible in Settings on every device.
3. The one-time import from Subsurface is free, works on iOS, and
   never stores the user's Subsurface password.
4. No force-push, ever. No write that loses data Subsurface recorded
   unless the user asked for that one dive explicitly.
5. The app drops `git2dart`, `git2dart_binaries`, `ffi` and
   `ssl_certs.dart`.
6. The service is the standing home for all future backend work (see §4).

Non-goals (this version):

- Reading edits back from Subsurface after the bootstrap import.
  Anchorline is the system of record; Subsurface is the backup copy.
- Mapping Anchorline's merged dives onto Subsurface's multi-segment
  format. Merged dives stay separate dives in Subsurface.
- Photos or attachments in Subsurface.
- Subscriptions and entitlements themselves. This spec only names the
  hook where that gate goes.
- Moving Postgres or PowerSync off Supabase.

Anti-goals (would make this a failure even if it worked):

- Any path that force-pushes or rewrites Subsurface history.
- Logging, crash-reporting or metrics that could contain a Subsurface
  password, even once.
- A sync cadence that a volunteer-run service would notice.
- A second implementation of the Subsurface format in another language.

## 3. Decisions made with Egbert (2026-11-02)

| # | Question | Decision |
|---|---|---|
| 1 | Sync at import time? | No. Subsurface can wait; nothing happens when a dive is imported. |
| 2 | Manual or automatic? | Automatic, on the server's schedule. "Sync now" stays as an escape hatch. |
| 3 | Direction | Anchorline → Subsurface only, after a one-time bootstrap import. Subsurface is "the backup app". |
| 4 | Credentials | The server stores the Subsurface email and password, encrypted per user with a master key outside the database. Consent screen, privacy-policy line, "Disconnect Subsurface" revokes. The free import never stores them. |
| 5 | Where it runs | A separate container on the existing Hetzner CX32 shared with De Spaankamer's site, behind that box's Caddy. |
| 6 | Backend language | Dart, compiled to a native binary. This is the backend stack for the foreseeable future; no Go or Rust on the roadmap. The Cloudflare Worker (TypeScript) is frozen at R2 presigning. The website is a separate Next.js project. |
| 7 | Free one-way import | Server-side for everyone, which gives iPhone the import. Requires a free Anchorline account. Free and paid accounts convert either way. |
| 8 | Politeness | Per-user mirror with incremental fetch, daily at most and only on change, global concurrency cap, identifying User-Agent. A note to the Subsurface maintainers before public launch, mentioning Egbert's long-standing sponsorship. |
| 9 | Skipped dives | A dive skipped for a foreign-edit conflict can be force-replaced from the app, per dive ("Replace in Subsurface"). |
| 10 | Deletes | The mirror follows deletes, but only for dives Anchorline itself synced. |
| 11 | Access gate | None until public launch; then an allow-list Egbert controls; then entitlements once built. |
| 12 | Cadence knob | Generous now (four users); tightened server-side as the user base grows. |

The line "Two-way Subsurface sync ... works on the user's device against
Subsurface's servers" in `docs/RELEASE_AND_MONETISATION.md` becomes
untrue with this design: ongoing sync now costs Anchorline server time
and disk. The paywall on it is therefore no longer honour-system only.
That doc gets a one-line update when this ships.

## 4. Standing decision: the backend stack

Recorded here so no later feature re-opens it.

- **One long-running Dart service**, `server/` in this repository,
  compiled with `dart compile exe`, running in a Debian-slim container
  with `git` installed. HTTP via `shelf` (Dart team), Postgres via the
  `postgres` package, crypto via `cryptography` or `pointycastle`, Sentry
  via `sentry` (the pure-Dart package). Nothing else without a reason.
- **It hosts every future backend need** as further routes and job
  types: entitlement webhooks from RevenueCat and Paddle, account
  deletion and GDPR export, the six-month purge after a lapse,
  server-side reparse of raw blobs, server-side exports. The reason is
  that half of these need the Shearwater parser, the sample codec, the
  Subsurface format or the deco model, which exist only in Dart.
- **Frozen:** the Cloudflare Worker (`worker/`) keeps presigning R2 URLs
  and gets no new features. It may be folded into the service later.
- **Unchanged:** Supabase Postgres and Auth, PowerSync. The service
  connects to Postgres directly; a later move to Hetzner Postgres is a
  connection-string change.
- **Not the backend:** the public website, planned as Next.js in its
  own container on the same box. It calls Supabase and the service's
  HTTP API where it needs account state.
- **Where Dart would not do:** code that must run at the edge
  (Cloudflare), or a job needing a native library with no Dart path.
  Neither is planned.

## 5. Architecture

```
┌──────────────┐  Supabase JWT   ┌────────────────────────┐  git https   ┌──────────────────┐
│  Anchorline  │ ──────────────▶ │  anchorline-server     │ ───────────▶ │ Subsurface Cloud │
│  app (all    │   HTTPS API     │  (Dart, Hetzner CX32)  │   basic auth │ ssrf-cloud-eu…   │
│  platforms)  │ ◀────────────── │                        │ ◀─────────── │                  │
└──────┬───────┘  job results    └───┬────────────┬───────┘              └──────────────────┘
       │                             │            │
       │ PowerSync                   │ SQL        │ disk: /var/lib/anchorline/repos/<user>/
       ▼                             ▼            ▼
┌──────────────────────────────────────────┐   per-user bare mirrors
│  Supabase Postgres (+ Auth, RLS)          │
│  dives, dive_samples, annotations, …      │
│  subsurface_connections (ciphertext)      │
│  subsurface_sync_state  (synced to app)   │
│  subsurface_sync_dives  (synced to app)   │
│  subsurface_jobs                          │
└──────────────────────────────────────────┘
```

Two flows:

**Ongoing sync (paid).** A scheduler in the service picks users whose
`dives`, `dive_annotations`, `dive_cylinders` or related rows changed
since their last successful run, at most once a day each, and enqueues
a `sync` job. The job fetches the user's mirror, checks out a temporary
working tree, reads the user's Anchorline state from Postgres, runs the
shared planner, writes files, commits, pushes, and writes the outcome to
`subsurface_sync_state` and `subsurface_sync_dives`. PowerSync carries
those rows to every device.

**One-time import (free and paid).** The app posts an `import` job with
the Subsurface email, password and region. The service clones (or
fetches, if a mirror exists) into a temporary directory, parses every
dive folder with the shared parser and read-mapper, and stores the
result as a gzipped JSON document. The app polls the job, downloads the
result, and commits each dive locally through `DiveDao.importDive` with
the existing Subsurface sentinel parser version. For paid users the
local commit then syncs up through PowerSync as normal. The password is
held in memory for the duration of the clone only. The temporary
directory and the result document are deleted after download or after
24 hours.

## 6. Shared package: `packages/subsurface_core`

The app and the server must agree byte for byte on the Subsurface
format, so the format code lives once, in a pure-Dart package inside
this repository, with no Flutter, Drift, PowerSync or I/O imports.

Moves out of `lib/sync/subsurface_git/` into the package:

- `format/` (parser, serializer, unit parsing, `SsLine` model).
- `mapper.dart` (Anchorline → Subsurface) and
  `subsurface_to_ccrlog_mapper.dart` (Subsurface → Anchorline).
- `sync_planner.dart`, `remote_snapshot.dart` (the snapshot becomes
  "parse these files" with the directory walk injected, so it stays
  I/O-free).
- The domain models they need: `lib/data/models/dive.dart`,
  `sample_set.dart`, `annotation.dart`, `equipment.dart` and the
  `lib/data/sample_codec/` package, which are already pure Dart. The
  Shearwater parser's `constants.dart`, `hardware.dart`,
  `dive_converter.dart` and `parsed_dive.dart` come along because the
  read-mapper produces a `ConvertedDive`. The parser directory is
  already pure Dart by rule, so this is a move, not a rewrite.
  `annotation.dart` imports Drift's `Value` wrapper for its copy-with
  helper; replace that with a small local sentinel so the package has
  no Drift import.

Builder's call, with a constraint: `mapper.dart` and `sync_planner.dart`
today take the Drift-generated row types `Dive`, `Cylinder` and
`DiveComputer` from `database.dart`. The package must not depend on the
generated database. Introduce plain input records (the fields the
mapper actually reads) and have the app build them from Drift rows and
the server from Postgres rows. The existing tests in
`test/sync/subsurface_git/` move with the code and keep passing; the
real-repo fixtures are the contract.

What stays in the app: `credentials.dart` (now only the email and the
region, used for the import request form), the Settings UI, the
import-result committer. What is deleted once the server path ships:
`repo.dart`, `ssl_certs.dart`, `sync_orchestrator.dart`, the
`bootstrap_importer.dart` git path, the `git2dart`, `git2dart_binaries`
and `ffi` dependencies, and the iOS "not supported" notice.

## 7. The service

### 7.1 Shape

One binary, three roles in one process: HTTP API, scheduler, job
runner. No separate queue service; the queue is the `subsurface_jobs`
table with `SELECT ... FOR UPDATE SKIP LOCKED`. One process is enough
for years at this scale; if that ever changes, a second container runs
the same binary with the API role off.

Configuration by environment variables only: `DATABASE_URL`,
`SUPABASE_JWKS_URL`, `MASTER_KEY` (32 bytes, base64), `REPO_ROOT`,
`SENTRY_DSN`, `MAX_CONCURRENT_JOBS`, `SYNC_MIN_INTERVAL`,
`SYNC_NOW_MIN_INTERVAL`, `IMPORT_MIN_INTERVAL`, `ACCESS_MODE`
(`open` | `allowlist` | `entitlement`).

### 7.2 Authentication and the gate

Every API request carries the Supabase JWT the app already holds; the
service verifies it against Supabase's JWKS exactly as `worker/src/jwt.ts`
does and takes `sub` as the user id. Row-level security is not relied
on for the service's own tables: the service uses a dedicated Postgres
role with direct grants, and filters by user id itself.

Gate, evaluated for `sync` only (the import is free):

- `open`: everyone. Setting until public launch.
- `allowlist`: user ids in `subsurface_allowlist`, managed by Egbert with
  SQL or a tiny admin route. Setting at launch.
- `entitlement`: whatever the subscriptions spec defines as "has paid",
  once that exists. The service exposes a single `bool hasSync(userId)`
  seam so the switch is one function.

### 7.3 Jobs

`subsurface_jobs` rows: `id`, `owner_id`, `kind` (`sync` | `import` |
`replace`), `state` (`queued` | `running` | `done` | `failed`),
`requested_by` (`scheduler` | `user`), `created_at`, `started_at`,
`finished_at`, `attempt`, `error_code`, `error_message`, `payload`
(jsonb, never contains a credential), `result_key`. Import jobs carry the
credential in process memory only, keyed by job id, never in the row;
if the process restarts, the queued import fails with
`credential_lost` and the app re-asks.

Runner rules:

- `MAX_CONCURRENT_JOBS` global, default 2. One job per user at a time.
- Retries: network and git transport errors retry up to 3 times with
  backoff; authentication failures do not retry and mark the connection
  `auth_failed` so the user is prompted; planner aborts are not errors.
- A job holds a working directory under `REPO_ROOT/work/<job id>/`,
  removed on completion whatever the outcome.
- Wall-clock limit 15 minutes per job; a first clone of a large repo is
  the only thing expected to approach it.

### 7.4 Git

The system `git` binary, invoked as a subprocess, never a library.

- Mirror: `REPO_ROOT/repos/<owner_id>.git`, a bare mirror of the user's
  branch. Subsurface names the branch with the literal email; the
  existing `repo.dart` reads it from the remote `HEAD`, keep that.
  First use clones; later runs `git fetch`. Incremental by nature.
- Working tree per job: `git worktree add` from the mirror, or
  `git clone --shared` into the job directory. Either is fine; the
  mirror is never modified except by fetch and by receiving the job's
  commit.
- Credentials are passed with `GIT_ASKPASS` pointing at a tiny helper
  that reads them from an environment variable scoped to that
  subprocess, or with a per-job credential file created `0600` and
  deleted immediately after. Never on the command line, never in the
  URL, never in `.git/config`.
- `User-Agent: Anchorline-sync/<version> (+https://<website>/subsurface-sync)`
  via `http.userAgent` config for the subprocess.
- Commit author name `Anchorline` from the first server commit on
  (decided with Egbert 2026-11-02; the name is final, the address is
  a noreply placeholder until the Anchorline domain is bought and is
  then updated once). The earlier `CCRLog` identity is still
  recognised wherever the spec says "Anchorline's or CCRLog's author
  identity". Commit message
  `Anchorline sync: N dives updated, M added, K removed`.
- Push is a plain `git push origin <branch>`. Never `--force`, never
  `--force-with-lease`, never a ref rewrite. A non-fast-forward rejection
  means someone pushed in between: fetch, re-plan, retry up to 3 times,
  then fail the job with `diverged` for a human to look at.
- Before every push the job tags the pre-sync remote head as
  `refs/anchorline/backup/<utc timestamp>` in the local mirror only.
  Not pushed. Keeps the last 30 per user. This is the "oops" lever: a
  bad write can be recovered on the server by a human without
  involving Subsurface.
- Region: the connection row stores `region` (`eu` default, `us`,
  `asia`). Builder verifies whether `cloud.subsurface-divelog.org`
  redirects by account and whether the app can detect the region at
  connect time; if not, the connect screen offers a region picker.

### 7.5 Write safety

The planner's existing rules move to the server unchanged and stay the
law:

- A dive that exists in Subsurface is matched by `(serial, start time)`
  and keeps its folder and `Dive-NNN` number.
- The `Divecomputer` file of an existing dive is never rewritten when
  Subsurface recorded it (`AbortReason.divecomputerProtected`), except
  by an explicit `replace` job. A `Divecomputer` file that Anchorline
  itself wrote, recognised by the planner's existing CCRLog-origin
  signature *and* confirmed by git history (the file's last commit has
  Anchorline's or CCRLog's author identity), may be rewritten
  unattended: that is the planner's existing self-repair for files an
  old build wrote wrong, and it is Anchorline's own data, not
  Subsurface's. Such a rewrite is recorded as `repaired` in
  `subsurface_sync_dives`. Note for the builder: today
  `divecomputerProtected` is declared but never raised; the server
  must raise it for the Subsurface-recorded case.
- A `Dive-NNN` file whose lines Anchorline does not own differ from what
  Anchorline would write is skipped (`AbortReason.foreignEditConflict`)
  and reported with the conflicting keys.
- Top-level `divecomputerid` lines are deduplicated by serial and the
  existing line wins.
- Skips are not failures: the rest of the run commits.

New in this version:

- **Replace.** A `replace` job carries one dive id. The planner runs with
  that dive marked `force`, which rewrites both files for that dive.
  Because it is an ordinary commit, the previous content stays in the
  repo's history. The app offers this only for dives listed as skipped.
- **Deletes.** When a dive is soft-deleted in Anchorline, the next sync
  removes its folder only if Anchorline *created* that folder. The
  service decides that from the repository itself, not from any
  Anchorline column: the commit that added the folder must have
  Anchorline's (or the earlier CCRLog) author identity. This covers
  dives pushed by the current in-app path without a backfill, and it
  never matches a folder Subsurface recorded, even one Anchorline later
  merged owned lines into. `dives.subsurface_uploaded_at` is not used
  for this: the current planner stamps it for merged dives too. If the
  folder meanwhile contains files Anchorline did not write (a second
  `Divecomputer` from another dive computer, say), the delete is
  skipped and reported like a conflict. Un-deleting a dive in Anchorline
  re-adds it. `subsurface_sync_dives.created_by_anchorline` caches the
  git-derived answer for the app's benefit.
- **Merges.** Merged dives (display-only groups with a synthetic id, see
  the "Merged dives use a synthetic id" memory) are emitted as their
  member dives. No change from today.
- **Sample fidelity.** The serializer must emit `dc_supplied_ppo2=` per
  sample where the dive computer supplied it, as Subsurface's own
  Petrel-3 import does; the 2026-05-08 corruption came from emitting
  rounded `po2=` steps instead. The round-trip test against the real
  repo fixture is the guard: parse → serialize must be byte-identical
  for every fixture dive.

### 7.6 Scheduling and rate limits

- Scheduler tick every 5 minutes. For each connected user with
  `last_success_at` older than `SYNC_MIN_INTERVAL` (default 24 h) whose
  change marker moved since `last_success_at`, enqueue a `sync` job
  with a random delay of up to 6 hours so runs spread across the day.
  The change marker is the greatest of `updated_at` and `deleted_at`
  across `dive_annotations`, `dive_cylinders`, `cylinders` and
  `dive_computers`, and of `imported_at` and `deleted_at` on `dives`
  (imported data has no `updated_at`; it is immutable), for that
  owner.
- "Sync now": at most once per `SYNC_NOW_MIN_INTERVAL` (default 10 min)
  per user; the API returns `429` with a `retry_after` otherwise.
- Import: at most once per `IMPORT_MIN_INTERVAL` (default 1 h) per
  account, and five failed authentications per account per day before
  imports are refused for 24 h. This is the brute-force guard.
- All intervals are environment variables so Egbert can tighten them
  without a release.

### 7.7 Credentials at rest

- Table `subsurface_connections`: `owner_id` (pk), `email`, `region`,
  `password_ciphertext` (bytea), `data_key_wrapped` (bytea), `key_version`
  (int), `created_at`, `updated_at`, `status`
  (`connected` | `auth_failed` | `disconnected`).
- Envelope encryption: a random 32-byte data key per connection,
  AES-256-GCM encrypts the password with it; the data key is wrapped
  with the `MASTER_KEY` from the environment, also AES-256-GCM, with
  the owner id as associated data so a row cannot be swapped between
  users. `key_version` allows rotating the master key by re-wrapping
  data keys without touching passwords.
- The master key lives in the container's `.env` on the Hetzner box,
  mode `0600`, owned by the deploy user, and in Egbert's password
  manager. Never in the repository, never in Postgres, never in Sentry.
- Decrypted passwords live in a Dart `Uint8List` for the duration of a
  git subprocess and are overwritten with zeros afterwards. They are
  never placed in a `String` that could end up in an exception message.
- Logging rule, enforced by a test: the log formatter and the Sentry
  `beforeSend` hook reject any event whose payload contains the
  password bytes or the string `password=`. Git subprocess stderr is
  captured, scrubbed of anything after `://` up to `@`, then logged.
- "Disconnect Subsurface" in the app calls `DELETE /subsurface/connection`,
  which deletes the row, the mirror directory, and any queued jobs, and
  sets `subsurface_sync_state.status = disconnected`.
- Account deletion (future, same service) must delete the same three
  things; the spec for that feature references this section.

### 7.8 Status back to the app

Two tables synced through PowerSync (sync rules and migration grants
required, per CLAUDE.md principle 7):

- `subsurface_sync_state` (one row per owner): `owner_id`, `status`
  (`disconnected` | `connected` | `auth_failed` | `error`), `email`,
  `last_run_at`, `last_success_at`, `last_error_code`, `last_error_message`
  (user-safe text), `dives_in_subsurface`, `dives_skipped`, `updated_at`.
- `subsurface_sync_dives` (one row per dive the service has touched):
  `id` = dive id, `owner_id`, `state` (`synced` | `repaired` | `skipped`
  | `removed`), `skip_reason`, `conflicting_keys` (jsonb), `folder`,
  `dive_number`, `created_by_anchorline` (bool), `synced_at`,
  `updated_at`. This replaces the `dives.subsurface_uploaded_at`
  column, which stays for one release for migration and is then
  dropped.

The service writes these; the app only reads them. PowerSync's upload
path for these tables is therefore disabled client-side (read-only
tables in the sync rules). The free import does not use them: its
status is the job row, polled over HTTPS.

### 7.9 HTTP API

All routes under `/v1`, JSON, bearer JWT. Errors `{ "error": "<code>",
"message": "<user-safe text>" }`.

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/subsurface/connection` | Body `{email, password, region}`. Verifies by an authenticated `git ls-remote`, stores encrypted, enqueues a first `sync`. Gate applies. |
| `DELETE` | `/subsurface/connection` | Disconnect, see §7.7. |
| `POST` | `/subsurface/sync` | "Sync now". `202` with job id, or `429`. Gate applies. |
| `POST` | `/subsurface/replace` | Body `{dive_id}`. Enqueues a `replace` job. Gate applies. |
| `POST` | `/subsurface/import` | Body `{email, password, region}`. `202` with job id. Free. |
| `GET` | `/jobs/{id}` | Job state, progress text, and for a finished import the result download URL. |
| `GET` | `/jobs/{id}/result` | The gzipped JSON import result, once. Deleted after download or 24 h. |
| `GET` | `/healthz` | Liveness: DB reachable, `git --version` works, `REPO_ROOT` writable. |

The import result format is a versioned JSON document (`"version": 1`)
listing dives in the shape `ImportedSubsurfaceDive` already produces
(converted dive, annotation, proposed cylinders), with samples as the
same base64 gzipped columnar blobs PowerSync uses. The app's committer
dedupes by `(dcSerial, startTimeUtcSec)` exactly as
`bootstrap_importer.dart` does today, so a re-import is additive.

## 8. App changes

- Settings → Subsurface section rewritten on top of the API and the two
  synced tables: Connect (email, password, region, consent text),
  status block, "Sync now", skipped-dives list with "Replace in
  Subsurface", Disconnect. Same section on every platform; the iOS
  notice goes away.
- Import from Subsurface: a form (email, password, region) that posts
  the job, shows progress, downloads the result and commits dives
  locally. Signed-in only, with the existing "sign in first" guidance
  from CLAUDE.md turned into a hard requirement in the UI.
- Dive detail: a small "In Subsurface" / "Skipped" indicator from
  `subsurface_sync_dives`.
- Consent copy, shown once at Connect and linked from Settings: "To
  keep Subsurface in step automatically, Anchorline stores your
  Subsurface Cloud email and password on Anchorline's server, encrypted.
  Disconnect at any time to delete them."
- `docs/PRIVACY.md` §7 rewritten: the credential is stored encrypted on
  Anchorline's server for connected accounts; the import uses it once
  and does not store it; what is deleted on disconnect.
- `credentials.dart` shrinks to remembering the email and region
  locally; the password is no longer kept on the device at all. (Today
  it is in the OS keychain; after this change it is only typed into the
  Connect or Import form.)

## 9. Deployment and operations

Mirrors De Spaankamer's pattern (`/Users/egbert/Dev/nextjs/SpaankamerWeb`,
`docker-compose.prod.yml`, `docs/deployment.md`) so there is one way of
running things on that box.

- `server/Dockerfile`: multi-stage, `dart:stable` to compile,
  `debian:bookworm-slim` + `git` + `ca-certificates` to run, non-root
  user. Image pushed to GHCR by a GitHub Actions workflow on tags
  `server-v*`.
- **Its own compose project**, not a service inside Spaankamer's file.
  Spaankamer's deploy workflow (`.github/workflows/deploy.yml` in that
  repo) copies its `docker-compose.prod.yml` and `Caddyfile` to the box
  on every deploy and runs `up -d --remove-orphans`, so anything added
  to that project by hand is wiped. The service therefore lives in
  `/opt/anchorline/docker-compose.yml` (committed in this repo under
  `server/deploy/`), with its own `.env`, a named volume for
  `REPO_ROOT`, and it joins Spaankamer's `external` Docker network as an
  external network so Caddy can reach it. Spaankamer's deploys cannot
  remove it or restart it.
- **Caddy:** one commit to the SpaankamerWeb repo adds
  `import /etc/caddy/sites/*.caddy` to its `Caddyfile` and mounts
  `/opt/caddy-sites` read-only. Anchorline's site block for
  `api.<anchorline domain>` lives in `/opt/caddy-sites/anchorline.caddy`,
  deployed by this repo. That is the only change Anchorline ever makes
  to the Spaankamer repo. The domain is still an open item in the
  release doc; until then a subdomain of despaankamer.nl is acceptable
  for the four current users, and the app's base URL is a config
  constant.
- **Deploy:** a GitHub Actions workflow in this repo builds the image on
  `server-v*` tags, pushes it to GHCR (private), and over SSH runs
  `docker compose pull && up -d` in `/opt/anchorline`, mirroring
  Spaankamer's workflow. The box logs in to GHCR with a read-only token
  stored in `/opt/anchorline/.env`.
- Database: the service connects to Supabase Postgres over the session
  pooler (`aws-0-eu-west-1.pooler.supabase.com:5432`, user
  `postgres.<ref>`) with its own role `anchorline_server`, created by a
  migration with explicit grants on exactly the tables it needs
  (`supabase/lint_migrations.sh` enforces the grant rule). Supabase's
  `postgres` user cannot grant `BYPASSRLS`, so the role gets
  role-targeted `select` policies on the dive tables it reads and full
  policies on its own tables; its password is set by hand on the
  dashboard, never committed. It never uses the service-role key.
- Migrations: the next free number after the gas-analyzer labels PR
  (`0020` is taken; expect `0021_subsurface_sync_service.sql`) creates
  `subsurface_connections`, `subsurface_jobs`, `subsurface_sync_state`,
  `subsurface_sync_dives`, `subsurface_allowlist`, the role and the
  grants; `infra/powersync-sync-rules.yaml` gains the two synced tables.
  Only the two status tables are in the sync rules; the connections
  and jobs tables are never replicated to devices.
- Backups: the mirrors are rebuildable from Subsurface, so the volume is
  not backed up. The connections table is in Supabase's backups
  (ciphertext only). The master key is backed up in the password
  manager; losing it means every user reconnects, nothing worse.
- Monitoring: Sentry (pure-Dart SDK) for exceptions with the scrubbing
  hook from §7.7; `/healthz` polled by an uptime check; a daily log line
  with counts of jobs by outcome. Alerts to Egbert's email on
  `diverged`, on any job over 10 minutes, and on five `auth_failed`
  across different users in an hour (which would mean Subsurface
  changed something).
- Disk: a mirror is about 4 MB per 700-dive user (measured on Egbert's
  repo: 579 commits, 3.96 MiB packed). The purge job deletes mirrors
  and connections of accounts lapsed for six months, in line with the
  monetisation decision.
- Upgrades: `docker compose pull && docker compose up -d
  anchorline-server`. A running job is allowed to finish (SIGTERM
  handler drains up to the job time limit).

## 10. Rollout

Each step is its own plan and PR set; the order isolates risk.

1. **Package split.** `packages/subsurface_core` with the moved code,
   plain input records, all existing tests passing. App behaviour
   unchanged. Pure refactor.
2. **Server skeleton.** `server/` with config, JWT verification,
   `/healthz`, Postgres connection, job table and runner, Dockerfile,
   compose entry, deployed to the box in `open` mode. No Subsurface
   routes yet.
3. **Import job.** `/subsurface/import` end to end, app-side form and
   committer, on all platforms. This is the first user-visible win:
   iPhone gets the free import. The in-app git bootstrap stays as a
   fallback for one release.
4. **Sync job.** Connection storage, scheduler, `sync` and `replace`,
   the two synced tables, the Settings rewrite. The in-app write path is
   removed in the same release; two writers to one repo is exactly the
   situation to avoid.
5. **Clean-up.** Delete `repo.dart`, `ssl_certs.dart`, the git
   dependencies and the iOS notice; drop `dives.subsurface_uploaded_at`;
   update CLAUDE.md, `docs/PRIVACY.md`, `docs/RELEASE_AND_MONETISATION.md`
   and `docs/subsurface_git_library.md` (mark superseded).
6. **Before public launch.** Switch `ACCESS_MODE` to `allowlist`; send
   the note to the Subsurface maintainers.

Until step 4 ships, the app's current planner-with-aborts write path
stays as it is on main. Note: the CLAUDE.md paragraph "A safety hold is
currently in place in `sync_orchestrator.dart` that throws
unconditionally" is stale; main has no such throw, the merge-mode
planner with per-dive aborts shipped 2026-05-11. Step 5 corrects it.

## 11. Testing

- `packages/subsurface_core`: the moved unit tests plus the byte-exact
  round-trip test over every dive in the fixture corpus.
- **Fixture corpus (decided with Egbert 2026-11-02): an anonymised
  subset of his real Subsurface repo, committed under
  `test/fixtures/subsurface/corpus/`.** A script in `tool/` takes a
  checkout of the real repo and a list of dive folders and writes
  copies with personal fields removed or replaced: `notes`, `buddy`,
  `divemaster`, `suit`, site names, GPS coordinates (replaced by
  fixed fake positions), the email in the branch name and in
  `00-Subsurface`, and any free-text `keyvalue` lines. Samples,
  events, cylinders, dive-computer metadata and timestamps stay
  byte-identical, since those are what the round-trip test guards.
  The builder picks the subset to cover: OC and CCR dives, dives with
  a second `Divecomputer`, dives Anchorline created versus dives
  Subsurface recorded, dives with foreign edits, the oldest format
  variant in the repo, and the `subsurface_incident_replica` case.
  Egbert reviews the generated files before they are committed, and
  the script is re-runnable so the corpus can grow. The real repo
  itself is never committed and never referenced by CI.
- Server: unit tests for the envelope encryption (including the
  wrong-owner associated-data case), the JWT verifier, the scrubber,
  the rate limiter, and the scheduler's change-marker query against a
  disposable Postgres (a service container in CI; the workflow has no
  Postgres today, the server job adds one).
- Server integration test: a bare git repository on local disk stands
  in for Subsurface Cloud (`repo_test.dart` already does this with
  `file://` URLs); run import → connect → sync → replace → delete and
  assert on the resulting repository contents and on the status tables.
  A test that pushes from a second clone between fetch and push proves
  the non-fast-forward retry and the absence of `--force`.
- App: widget tests for the Settings section against a fake API and
  fake synced rows; a committer test that feeds a recorded import
  result and asserts the same dives as the current bootstrap importer
  produces.
- Manual, before step 4 ships: Egbert's own account against the real
  Subsurface Cloud, with a fresh clone of the cloud branch compared
  before and after by `git diff`.

## 12. Left to the builder

- Exact plain input record shapes for the mapper and planner.
- Worktree vs shared-clone choice for job checkouts.
- `GIT_ASKPASS` helper vs per-job credential file.
- Whether region can be auto-detected; otherwise the picker.
- Progress granularity reported on the job row.
- Dart server package choices within the constraints of §4.
- Compose service naming and the Caddy block, following the Spaankamer
  files.

## 13. Open items outside this spec

- The Anchorline domain (release doc open question) decides the API
  host name and the commit author email address.
- The entitlements spec decides what `hasSync(userId)` reads.
- Account deletion and GDPR export are future jobs in this service;
  §7.7 lists what they must remove for Subsurface.
