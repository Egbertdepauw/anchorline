# Subscriptions and entitlements — design

Date: 2026-10-07, revised 2026-11-18
Status: design approved in conversation; revised for what changed since;
awaiting spec review
Context: `docs/RELEASE_AND_MONETISATION.md` (goals, free/paid split,
channels, hosting, licence), and the backend service design in
`docs/superpowers/specs/2026-11-02-subsurface-sync-service-design.md`
(branch `spec/subsurface-sync-service`). Tracked in issue #259, milestone
"Store launch".

## What changed in the 2026-11-18 revision

- **Server code moves out of the Worker.** Since 2026-11-02, all new
  backend work goes into one Dart service (`server/`) on the Hetzner
  box, and the Cloudflare Worker is frozen at R2 presigning (standing
  decision, recorded in §4 of the Subsurface sync service spec). The
  sync pass, the billing webhook, the refresh route and the lapse job
  move to that service. The hourly sweep becomes a `pg_cron` job, as
  the purge of unconfirmed accounts already is (migration 0024). The
  service doesn't exist yet. Its skeleton is rollout step 2 of the
  Subsurface sync service spec, and this work depends on it.
- **The paid Subsurface feature is now "ongoing Subsurface sync", and
  the server can enforce it.** With the Subsurface sync service, ongoing
  sync runs on the server, one way, from Anchorline to Subsurface, after
  a one-time import. The one-time import stays free. The service's
  `hasSync(userId)` gate reads this spec's access summary. It is no
  longer honour-system once the service is doing the sync.
- **Account deletion exists** (`delete_my_account()`, migration 0022,
  PR #160). This spec now covers only what a subscription changes about
  it (§4).
- **Email:** Resend is already the sign-in mail provider (Supabase SMTP),
  so the lapse emails use Resend's HTTP API from the service.
- **The app already knows its distribution channel:**
  `BuildInfo.distribution` (`DISTRIBUTION_CHANNEL` = `app_store`,
  `play_store`, `website` or `none`).
- **The Worker has tests now** (`vitest`), and `/sign-upload` already
  enforces the per-account upload limits (#196).
- **Uploads refused by row-level security are retried, not quarantined**
  (`ccrlogger_backend_connector.dart`). They are reported to Sentry and
  shown as "Upload blocked by the server". §2 says how the app must tell
  a lapse apart from a server defect.
- **Store commission and fees** are updated in "Costs introduced".
- **A reviewer who hadn't seen the design read it cold.** The gaps they
  found are closed, each marked *My call* where it is decided:
  - sandbox purchases count, and the App Review account gets no grant
    (§1);
  - payment problems keep access for the stores' grace period only
    (§1);
  - the pass follows one access-mode switch in Postgres, so stage 7
    needs no app release, and accounts created before stage 7 keep
    syncing (§2, build order);
  - the write policies are split per table, because today one policy
    covers reads and writes (§2);
  - only cloud storage of attachment files is paid, and links and local
    files stay free; the 10 GB / 10,000-file limit for paying accounts
    comes from the upload-limits spec (§2);
  - a store subscription stays with the account that bought it (§3);
  - grant holders can subscribe in the 30 days before their grant ends
    (§3);
  - the webhook re-reads the state from RevenueCat on every event (§4);
  - no passes are issued while the 6-month deletion runs, and the
    service gets an R2 token for that deletion (§4);
  - the wording now matches the code: Settings → Sync (there is no
    Settings → Account), the policy names, and the `website` builds for
    the macOS `.dmg` and the Android `.apk`.
- **Two decisions taken by Egbert on 2026-11-18:**
  - the Worker gets a third freeze exception, for one attachment
    entitlement check (§2);
  - the store launch doesn't wait for the web checkout (stage 5) or the
    lapse handling (stage 6) (build order).

## Goal

Let an Anchorline account pay for a subscription on any platform and have
the paid features work on all of that person's devices, with the servers,
not the app, deciding who has access.

Success means:

- A free user loses nothing: the app works fully without an account,
  exactly as today.
- A subscription bought on one platform gives access on every platform.
- An account without access cannot sync or use attachments, even with a
  modified app.
- Ending a subscription never removes anything from a device.
- No user's logbook is lost by any transition: lapse, server deletion, or
  resubscribing afterwards.
- The owner can grant any account access, for a period or indefinitely.

## Decisions

| Question | Decision |
|---|---|
| What is paid? | Anchorline cloud sync, attachments, ongoing Subsurface sync. Everything else is free, including the one-time import from Subsurface. |
| Where does the server code run? | In the Dart service (`server/`), except the hourly sweep, which is a `pg_cron` job in Postgres. The Worker gets no new routes, only one access check on attachment signing (third freeze exception, 2026-11-18). |
| What happens when a subscription ends? | Sync and uploads stop. Every device keeps its local logbook. The server copy is kept for 6 months, with reminder emails, then deleted. |
| Free trial? | 30 days, with a payment method up front, using each channel's own trial mechanism. |
| Plans? | Yearly and monthly, same features, switchable. |
| Prices? | Decided later. Set in the store consoles and the web checkout, not in code. |
| Existing beta accounts? | Each gets a grant before enforcement is switched on. |
| Grants? | The owner can grant any account access until a chosen date or with no end date, and change or revoke it. |
| How are purchases unified? | A subscription service (RevenueCat) for the stores, a web checkout for Windows and Linux, both notifying the server. |
| Web checkout provider? | Paddle as billing engine behind RevenueCat's web purchase links, because Paddle acts as merchant of record and handles EU VAT. |

## Out of scope

- The actual prices.
- The website, beyond the checkout link the desktop apps open. It is its
  own project.
- Account deletion itself. It is built (`delete_my_account()`, PR #160);
  §4 adds only what a subscription changes about it.
- The service skeleton (deployment, JWT verification, job runner). It is
  rollout step 2 of the Subsurface sync service spec.
- Self-service data export, team or instructor plans, storage tiers.

## Current state

- The app is fully usable offline without sign-in. Signing in only
  enables cloud sync (`lib/sync/cloud/auth_service.dart`).
- Dives and samples live in the local PowerSync database whether or not
  the device is connected.
- `CloudSyncCoordinator` connects PowerSync when signed in and
  disconnects when not.
- `CcrloggerBackendConnector.fetchCredentials` hands PowerSync the
  ordinary Supabase session token. Any signed-in account can sync.
- Sync is scoped per user by `infra/powersync-sync-streams.yaml`
  (Sync Streams, `auth.user_id()`). Each of the 16 synced tables has a
  single row-level policy that covers reads and writes on its own rows.
  Ten are named `owner_full_access`, and six (`dive_bailout_carry`,
  `dive_plans`, `dive_merge_links`, `gas_analyses`,
  `user_acknowledgements`, `open_blends`) use other names. There is no
  separate write policy.
- There is one backend for every build: one Supabase project and one
  PowerSync instance. TestFlight, Play testing and store builds all use
  it.
- Sign-in, sync status and Delete account are in Settings → Sync. There
  is no Settings → Account.
- Two `website` builds exist besides Windows and Linux: the Developer ID
  macOS `.dmg` and the hosted Android `.apk`.
- Attachments go through the Cloudflare Worker (`worker/`), which
  verifies the Supabase JWT. Routes: `/sign-upload` (with the
  per-account quota, rate limit and kill switch from #196),
  `/sign-download`, `/delete`, `/usage`. Tests run with `vitest`.
- Uploads that row-level security refuses (Postgres `42501`) are retried
  rather than quarantined, reported to Sentry once per table and
  operation, and shown in the Sync tab as "Upload blocked by the server"
  (`lib/sync/cloud/ccrlogger_backend_connector.dart`).
- `public.delete_my_account()` (migration 0022) deletes the caller's rows
  and their `auth.users` row. Settings → Sync → Delete account calls it.
- `pg_cron` runs scheduled SQL already: the nightly purge of unconfirmed
  accounts (migration 0024).
- The app knows how it was distributed: `BuildInfo.distribution` in
  `lib/build_info.dart`, from the `DISTRIBUTION_CHANNEL` dart-define.
- Resend sends Supabase's sign-in emails over SMTP.
- The Dart service (`server/`) is designed but not built.
- No purchase library and no entitlement table exist.

## Design

Wording: "the service" is Anchorline's Dart backend service (`server/`),
and "the subscription service" is RevenueCat.

### 1. The entitlement record

**Access sources.** Table `entitlement_sources`, one row per account per
source:

| Column | Meaning |
|---|---|
| `user_id` | The account (`auth.users.id`) |
| `source` | `app_store`, `play_store`, `web`, or `grant` |
| `state` | `trial`, `active`, `payment_problem`, or `ended` |
| `product` | `monthly` or `yearly`; null for a grant |
| `access_until` | When this source's access ends. Null means no end and is allowed only for a grant |
| `provider_ref` | The subscription service's reference; null for a grant |
| `environment` | `production` or `sandbox`, from RevenueCat; null for a grant |
| `note` | Free text, used for grants |
| `created_at`, `updated_at` | |

Unique on (`user_id`, `source`).

**Sandbox purchases count.** There is one backend, so purchases made
through TestFlight, Play license testers and App Review reach the
production webhook as sandbox events. They are honoured like real ones
and recorded with `environment = sandbox`. App Review must be able to
complete a purchase on its review account, which therefore gets no
grant. Sandbox subscriptions renew on a shortened schedule and stop
after a few renewals, so the access they give runs out within hours to
days. Only people Egbert invites as testers can make them. *My call: a
separate staging backend isn't worth it for this.*

**Account summary.** Table `account_access`, one row per account,
derived from the sources:

| Column | Meaning |
|---|---|
| `user_id` | The account |
| `has_access` | True if any source is current |
| `access_until` | The latest end among current sources; null if a current source has no end |
| `reason` | The source that gives the latest access |
| `trial_used` | True once any source has been in `trial` |
| `ended_at` | When `has_access` last became false; null while it is true. The 6-month clock runs from here |
| `data_generation` | An integer that increases each time this account's server copy is deleted (section 2) |
| `deletion_state` | Null, or `running` while the 6-month deletion is in progress (§4) |
| `quota_bytes`, `quota_files` | Attachment limit overrides for this account; null means the default. They replace the Worker's `QUOTA_OVERRIDES` variable, as the upload-limits spec foresaw |
| `updated_at` | |

**Rules**

- An account has access if at least one source is current: its state is
  `trial`, `active` or `payment_problem`, and its `access_until` is null
  or in the future.
- Only the server writes either table: the service, through its
  Postgres role `anchorline_server`, and the hourly `pg_cron` sweep. The
  summary is recomputed by one SQL function whenever a source changes,
  and by the sweep, which ends anything past its date. A device's clock
  is never trusted.
- An account may read its own `account_access` row and nothing else.
  Both tables need explicit grants in their migration, to
  `authenticated` (select on `account_access` only, through a policy on
  `user_id = auth.uid()`) and to `anchorline_server`
  (`supabase/README.md`, issue #76). They are not synced, so the
  `primary key (owner_id, id)` rule for synced tables doesn't apply.
  Both reference `auth.users(id) on delete cascade`, so account deletion
  removes them.
- These tables are **not** in the PowerSync sync rules. The summary must
  be readable while sync is off, so the app reads it over Supabase's REST
  API and caches the last value locally. This is a deliberate exception
  to "everything the user sees syncs": it is server state, not user
  data.

**States, as the user experiences them**

| State | Access | How it arises |
|---|---|---|
| Never subscribed | No | No sources |
| Trial | Yes | First 30 days of a subscription |
| Active | Yes | Paid and current |
| Payment problem | Yes, for the store's grace period | A renewal charge failed and is being retried |
| Granted | Yes | A grant from the owner |
| Ended | No | Cancelled and run out, refunded, or grant expired |

**Payment problems.** Billing grace periods are switched on in both
stores, about two weeks each, set in the consoles. A source in
`payment_problem` keeps access until the grace period ends; RevenueCat
reports that date as the expiry. After grace, the store's own retries
(Apple's billing retry, Play's account hold) give no access, and a
successful retry restores it. *My call: up to 60 days of free access
during retries is too generous, and no grace period at all is too
harsh.*

### 2. Enforcement

**Sync pass.** The app no longer hands PowerSync the Supabase session
token. It asks the service for a short-lived sync pass:

- New service route `POST /v1/sync-token`: verifies the Supabase JWT the
  same way as the service's other routes, and returns a JWT signed with
  a key held by the service, valid for at most one hour, or 403. Which
  one follows `server_settings.access_mode` (see the build order):
  - `open` (stages 2 to 6): a pass for every signed-in account;
  - `entitlement` (stage 7 onwards): a pass only if the account's
    `account_access.has_access` is true and its `deletion_state` is
    null.

  The response also says whether enforcement is on (`enforced: true`
  under `entitlement`), and the app caches that flag.
- The service publishes the matching public key as a JWKS document
  (`GET /.well-known/jwks.json` on the service's host, `api.anchorline.eu`),
  and the PowerSync instance is configured to accept tokens signed by it.
- Without a pass a device cannot connect. An account whose access ends
  keeps its current connection until the pass expires, at most one hour.
- The app renews the pass when half its lifetime has passed. A service
  outage shorter than that goes unnoticed; a longer one pauses syncing
  (§5). *My call: one hour, as before. A longer pass makes outages less
  visible and lapses slower to take effect.*

**Why not the sync rules.** Making the sync rules return nothing for an
account without access would be simpler, but when a device's data leaves
its sync set, PowerSync removes that data from the device. That would
wipe a lapsed user's logbook. Refusing the connection leaves the local
database untouched. This behaviour is to be confirmed by experiment
before anything is built (stage 0).

**Database writes.** Writes to every synced table additionally require
access, through one SQL function `has_sync_access(user_id)`. This is a
second lock against a modified app. Each table has one policy for reads
and writes today (Current state). At stage 7 each is replaced by:

- a `select` policy on own rows, as before;
- `insert`, `update` and `delete` policies on own rows, which also call
  `has_sync_access(owner_id)`.

The function returns true while `server_settings.access_mode` is not
`entitlement`, so the new policies can be deployed long before stage 7
without changing anything.

Reads stay as they are: an account can still read its own rows over
REST. That lets a lapsed user's data be exported on request and exposes
nothing that isn't theirs.

A write refused this way fails with the same Postgres code (`42501`) as
a server defect. Today the connector retries such a write, reports it to
Sentry and shows "Upload blocked by the server". When access ends while
a device is connected (at most one hour, until the pass expires), the
app must:

- on the first `42501`, refresh the access summary before reporting
  anything;
- if access has ended, disconnect, keep every queued change (nothing is
  quarantined or dropped), skip the Sentry report, and show that the
  subscription has ended instead of "blocked by the server";
- if access is still current, keep today's handling.

**The app.** The pass is the gate, so the server decides, and stage 7
is a server-side switch that needs no app release:

- `CloudSyncCoordinator` connects when signed in and it holds a pass.
- A 403 from `/v1/sync-token` means no access. The app stays
  disconnected and shows the offer. Without access it behaves as it does
  today when signed out: fully usable, with local changes waiting in the
  upload queue.
- If the service can't be reached, a timeout or a 5xx (never a 403),
  the app falls back to the Supabase token. Before stage 7 PowerSync
  accepts that token, so syncing carries on through service outages.
  From stage 7 PowerSync refuses it, and the fallback stops working on
  its own. *My call.*
- The cached summary drives what the app shows (plan, renewal date, the
  offer) and its offline behaviour. It is not what decides the
  connection.
- App-only gates, such as the in-app Subsurface write path, apply only
  while the cached `enforced` flag is true.

Accounts created after stage 1's grants therefore keep syncing until
stage 7, like everyone else.

**Server deletion and reconnecting.** After the 6-month deletion, a
device that reconnects would meet an empty server and could remove
everything it had previously synced. To prevent that:

- `account_access.data_generation` increases whenever an account's
  server copy is deleted.
- The app stores the generation it last synced against. Before
  connecting, it compares. If the server's value is higher, the app
  first queues its entire local logbook for upload, stores the new
  value, and only then connects.

Requirement: after a device with a synced logbook reconnects to an
account whose server copy was deleted, every row of every table in
`infra/powersync-sync-streams.yaml` that was on the device is still on
the device and is back on the server. Attachments whose file is on the
device are uploaded again with their file. An attachment whose file is
not on the device keeps its row and shows that the file is no longer
available (*my call*). How the full re-upload is queued depends on the
stage 0 findings and is designed in stage 3's plan.

**Attachments.** What is paid is cloud storage: uploading files to R2
and downloading them on another device. Adding link attachments, and
file attachments that stay on the device, remain free, as they are for
a signed-out user today. That keeps "a free user loses nothing". With
access ended: no uploads, and no downloads of files not already on the
device. Files already downloaded stay viewable, and deleting your own
files always works.

Limits, as the upload-limits spec (2026-11-10, §3) decided:
- an account with access gets 10 GB and 10,000 files;
- until enforcement, every confirmed account keeps today's 1 GB and
  1,000 files;
- per-account overrides move from `QUOTA_OVERRIDES` into
  `account_access.quota_bytes` and `quota_files`.

The attachment check reads the limit in the same call as the access.

**Where the attachment check lives (decided 2026-11-18).** Attachments
are signed by the Worker, which is frozen, and the 2026-11-10 freeze
exception for upload limits explicitly left entitlement checks out.
Egbert approved a **third freeze exception**, limited to this one check:
on `/sign-upload` and `/sign-download`, the Worker calls a Postgres
function `my_sync_access()` over Supabase's REST API with the user's own
JWT. The function returns the access and the limits. That adds no new
secret to the Worker and covers builds already in the wild. `/delete`
stays unchecked. The rejected option was moving attachment signing into
the service: builds from before the move would then lose attachments
entirely, not only for lapsed accounts.

**Subsurface.** The one-time import is always available. Ongoing sync
runs in the service, whose `hasSync(userId)` gate reads `account_access`
once `server_settings.access_mode` is `entitlement`, so the server
enforces it. Until
that service step ships, the app's own write path checks the cached
summary, as an honour-system gate.

### 3. Buying

**Account first.** A subscription belongs to an Anchorline account. The
app requires sign-in before showing prices, and gives the account's id
to the subscription service as the customer id. That is what makes a
purchase valid across platforms.

**Where the offer appears.** In Settings → Sync, where sign-in and the
sync status already are, and at the three points where a free user
reaches a paid feature: turning on sync, an attachment file that would
upload, and turning on ongoing Subsurface sync.

**The subscribe screen** shows both plans with prices fetched from the
channel (so they appear in the user's currency), the 30-day trial, a
"Restore purchases" button, and links to the terms and the privacy
policy.

| Distribution channel | Flow |
|---|---|
| `app_store` (iOS, Mac App Store), `play_store` (Google Play) | The store's purchase sheet, through the `purchases_flutter` library. Then "Activating…" until the server has recorded the purchase, then sync starts |
| `website` (Windows, Linux, the Developer ID macOS `.dmg`, the hosted Android `.apk`), `none` | "Subscribe" opens a web purchase link in the browser, carrying the account id. The app refreshes when it regains focus or the user presses "I've paid" |

`purchases_flutter` supports Android, iOS and macOS, not Windows or
Linux. The Windows and Linux apps contain no purchase code; they only
read the summary.

**The purchase method follows how the app was distributed, not the
operating system.** Apple's in-app purchase works only in App Store
builds, and Play Billing only in Play builds. The app reads its channel
from `BuildInfo.distribution`.

**Restoring on another Anchorline account.** RevenueCat's restore
behaviour is set to "keep with original App User ID". A store
subscription stays with the Anchorline account that bought it. If
"Restore purchases" finds a subscription that belongs to another
account, it says so and asks the person to sign in to that account.
Family Sharing is off. The webhook still handles `TRANSFER` events
defensively: it ends the source on the account the purchase left.
*My call: this follows "a subscription belongs to an Anchorline
account", and it prevents one store subscription being moved between
accounts.*

**After buying.** Settings → Sync shows the plan, the next renewal
date and where it was bought. Changing plan or cancelling happens where
the purchase was made: the app links to the App Store or Play
subscription page, or to Paddle's customer page, and on other platforms
says where to manage it. If an account already has access from any
source, no second purchase is offered. The one exception is an account
whose only current source is a grant that ends within 30 days. It sees
the offer, with the grant's end date. A reminder email goes out 14 days
before a grant ends. With the 30-day trial, buying early doesn't charge
twice. *My call: otherwise every beta tester would go through a lapse
before they could buy.*

**Store rules.** The `app_store` and `play_store` builds offer only
in-app purchase and do not mention or link to the web checkout.

**Trial limit.** The stores decide trial eligibility per store account.
The server records `trial_used`, and the web checkout then offers the
plan without a trial. This is best effort: someone could still take one
trial on a store and another elsewhere.

### 4. Server-side flows

All routes below are in the Dart service, under `/v1` like its other
routes, and every scheduled job except the hourly sweep is a job type in
its runner.

**Purchase notifications.** New route `POST /v1/billing/webhook`
receives the subscription service's events (trial started, renewed,
payment problem, cancelled, expired, refunded, product changed,
transferred). It rejects any request without the shared secret. It then
doesn't trust the event's own contents: it fetches the account's current
state from RevenueCat's API, upserts the matching
`entitlement_sources` row from that, and recomputes the summary.
Duplicates and out-of-order arrival are therefore harmless, and a
delayed event can't overwrite a newer state written by the sweep or by a
refresh. *My call: this replaces the earlier rule "an event older than
the row's last update is ignored", which would throw away a renewal that
arrived after a sweep.*

**Refresh on demand.** New route `POST /v1/billing/refresh`,
authenticated as the user: asks the subscription service directly for
that account's status and corrects the record. Called by "Restore
purchases", by "I've paid", and after a store purchase completes. This
covers lost or late notifications.

**Grants.** Three SQL functions, run from the Supabase SQL editor and
not executable by `authenticated` or `anon`:

- grant access to an email address, until a date or with no end, with a
  note;
- change or revoke a grant;
- list all grants.

**Hourly sweep.** A `pg_cron` job, following the pattern of migration
0024, ends any source past its `access_until` and recomputes the
affected summaries. It is plain SQL, so it doesn't depend on the service
being up.

**Lapse schedule.** A daily job in the service, for accounts whose
`ended_at` is set:

| When | Action |
|---|---|
| Day 0 | Email: sync has stopped, the logbook stays on the devices, the server copy is kept until a stated date |
| 30 days before deletion | Reminder email |
| 7 days before deletion | Final reminder |
| 6 months after `ended_at` | Delete the account's rows in every synced table and its attachment files, increase `data_generation`, send a confirmation email |

- The account and its entitlement history are kept, so the person can
  sign in and resubscribe, and `trial_used` survives.
- Gaining access before the deletion starts clears `ended_at` and
  cancels the schedule.
- The deletion runs in this order:
  1. Set `deletion_state = running`. From now on `/v1/sync-token`
     refuses passes, so no device can connect to a half-emptied server.
  2. Delete the account's attachment files in R2.
  3. In one transaction: delete the account's rows in every synced
     table, increase `data_generation`, and clear `deletion_state`.
  4. Send the confirmation email.

  A run that fails halfway stays `running` and repeats safely. If the
  person resubscribes while it runs, their access waits until step 3
  commits, a matter of minutes. Their first connection after that sees
  the higher generation and re-uploads the whole logbook. *My call:
  this closes the window the reviewer found, where a resubscribe during
  the deletion could reach an empty server before the generation
  changed.*
- R2 deletion needs credentials the service doesn't have yet: an R2 API
  token limited to the attachments bucket, with delete rights. This
  follows the account-deletion decision (PR #160) that the R2 orphan
  sweep moves into the service. The Worker stays the only signer for
  app uploads and downloads.
- The deletion step also removes the account's Subsurface mirror and
  stored Subsurface credentials in the service, as the Subsurface sync
  service spec's purge job describes.
- Emails go through Resend's HTTP API, the provider that already sends
  the sign-in emails. Its free tier (3,000 emails a month, 100 a day)
  covers this at the expected scale. They are sent from a no-reply
  address on anchorline.eu.

**Account deletion while subscribed.** Deleting the Anchorline account
doesn't cancel a store or Paddle subscription, and the stores keep
charging until the person cancels there. So:

- Before deletion, if the account has a store or web source that is
  `trial`, `active` or `payment_problem`, the delete screen says so and
  links to where to cancel (the same link as "manage subscription").
  Deletion stays possible.
- `delete_my_account()` removes both entitlement tables through the
  `on delete cascade`. Migration 0022 calls that function a stopgap,
  which moves into the service later. Whichever path deletes the account
  does the steps below. The service path also removes the Subsurface
  mirror, which a Postgres function can't.
- The service deletes the account's customer record at the subscription
  service, for GDPR. It finds those accounts through a small table of
  pending RevenueCat deletions that `delete_my_account()` fills before
  it deletes the user. *My call: this keeps the deletion function free
  of HTTP calls.*
- `trial_used` goes with the account. Someone could delete their account
  and take a second web trial. Store trials are tied to the store
  account, so they can't. Accepted.

**Existing accounts at launch.** Before stage 7, every existing account
gets a grant: no end date for the owner's, and a period chosen per beta
tester, including the testers of other dive-computer brands.

### 5. Failure handling

| Problem | Handling |
|---|---|
| Notification lost or late | RevenueCat retries; `/v1/billing/refresh` corrects on demand |
| Forged notification | Rejected without the shared secret |
| Refund or chargeback | Arrives as a notification; access ends at once |
| Service unavailable (the Hetzner box, a deploy, a crash) | No new sync passes. Passes renew at half their lifetime, so syncing pauses for everyone only after about 30 minutes of downtime. Local use is unaffected and changes queue. Purchases wait in RevenueCat, which retries the webhook. The hourly sweep keeps running, because it's in Postgres. Accepted as the cost of server-side enforcement; `/healthz` and the uptime check from the service spec catch it |
| Access ends while a device is connected | Writes fail with `42501` until the pass expires; the app refreshes the summary, disconnects and keeps the queue (§2) |
| Summary cannot be fetched (offline) | The app uses its cached summary until `access_until` |
| Deletion job fails midway | Safe to re-run; `data_generation` changes only at the end |
| Device offline for more than 6 months after a lapse | Its local logbook is intact; on resubscribing, the generation check triggers the full re-upload |

### 6. Testing

- **Stage 0 experiment**, on a real local PowerSync database: what
  happens to local rows when a device's data leaves its sync set, and
  when a device reconnects to an emptied server. If the result differs
  from the assumptions in section 2, the design is revised before any
  build stage.
- **SQL**: deriving the summary from sources, overlapping sources, grant
  with and without an end, the hourly sweep, `has_sync_access` in the
  write policies, the cascade on account deletion, and the split
  policies changing nothing while `access_mode` is `open`.
- **Service**: `/v1/sync-token` for accounts with and without access,
  the JWKS document, the webhook secret, duplicate and out-of-order
  events, a delayed event after a sweep, `TRANSFER`, sandbox events,
  refresh, the lapse schedule including a re-run after a simulated
  failure, no pass while `deletion_state` is `running`, and the
  RevenueCat deletion after account deletion.
- **Worker** (`vitest`, next to the upload-gate tests): the attachment
  check, for accounts with and without access, and while `access_mode`
  is `open`.
- **App**: the connect decision, the cached summary and its expiry, the
  `42501` handling when access ends while connected (queue kept, no
  Sentry report), the subscribe screen per distribution channel, hiding
  the offer when access exists, the delete-account warning for an
  active subscription.
- **Re-upload protection**, the most heavily tested part: a device with
  a synced logbook, a higher server `data_generation`, and an assertion
  that every record is still present locally and on the server after
  reconnecting.
- **Sandbox purchases** on each store and the web checkout: trial start,
  renewal, cancellation, refund, plan switch, restore on a second
  device.
- **Manual end-to-end pass** on all five platforms before stage 7.

## Build order

Each stage is its own plan and pull request. Existing users are
unaffected until stage 7.

**Prerequisite:** the service skeleton, which is rollout step 2 of the
Subsurface sync service spec (`server/`, JWT verification, `/healthz`,
Postgres role, job runner, Docker image, deploy to the Hetzner box
behind Caddy at `api.anchorline.eu`). Stages 0 and 1 don't need it, so
they can run while it is built. Stage 2 can't start without it.

The Subsurface sync service spec creates the `anchorline_server` role in
a migration it numbers `0021`, a number now taken; the newest migration
is `0028`. Whichever of the two lands first creates the role,
idempotently, in its own migration, and the other reuses it.

**One switch.** The access mode lives in Postgres, in a one-row table
`server_settings` (`access_mode`: `open`, `allowlist` or
`entitlement`). The service reads it there instead of from an
environment variable, and `has_sync_access()` and `my_sync_access()`
read it too, so stage 7 is a single change. `allowlist` applies only to
ongoing Subsurface sync, as in the Subsurface sync service spec. The
sync pass and the write policies treat it as `open`. *My call: this
amends §7.1 of that spec, where `ACCESS_MODE` is an environment
variable.*

| Stage | Adds | Needs the service? | Enforced? |
|---|---|---|---|
| 0 | The PowerSync experiment | No | No |
| 1 | `entitlement_sources`, `account_access`, `server_settings` (set to `open`), the grant functions, the hourly `pg_cron` sweep, `has_sync_access()`, each synced table's policy split into read and write policies (no effect while `open`), grants for all existing accounts, status shown in Settings → Sync | No | No |
| 2 | `/v1/sync-token`, the JWKS document, and the app using it. PowerSync accepts both the Supabase token and the pass | Yes | No |
| 3 | `data_generation` and the re-upload protection | No | No |
| 4 | Store purchases on iOS, macOS and Android, the subscribe screen, `/v1/billing/webhook`, `/v1/billing/refresh`, the `42501` handling, the delete-account warning | Yes | No |
| 5 | Web purchase link and the Windows and Linux flow | Yes | No |
| 6 | Lapse emails, the 6-month deletion job, the RevenueCat deletion after account deletion | Yes | No |
| 7 | `server_settings.access_mode` becomes `entitlement`, which switches on the sync pass check, the write policies and the attachment check together; in the PowerSync dashboard, the Supabase JWT is removed. No app release | Yes | Yes |

App versions from before stage 2 stop syncing at stage 7. Beta testers
need notice and an update first.

**What the store launch waits for (decided 2026-11-18).** Stages 0 to 4
and 7 are needed to sell anything. Stages 5 and 6 aren't needed on
launch day:

- Without stage 5, people using a `website` build (Windows, Linux, the
  Developer ID macOS `.dmg`, the hosted Android `.apk`) can only
  subscribe from a store build on another device. A subscription bought
  there works on every device.
- Without stage 6, nobody's access has lapsed yet: the first trials end
  30 days after launch, and the first deletion is due 6 months after
  that.

Egbert decided: the store launch follows stage 7 and does not wait for
stages 5 and 6. Stage 6's lapse emails ship within 30 days of launch,
before the first trials end, and stage 5 when it is ready. Running
stage 7 before 5 and 6 needs no change to the design. Until stage 5,
the subscribe screen in `website` builds says where to subscribe
instead of opening a link.

## Set up outside the code

Tracked in issues #256 (business setup), #257 (terms) and #258 (paid
hosting).

- Accounts with RevenueCat and Paddle. Paddle checks the website before
  approving it: anchorline.eu needs a pricing page, the terms, the
  privacy policy and a refund policy.
- Subscription products (monthly, yearly, 30-day trial) in App Store
  Connect and the Play Console, with each store's paid-apps agreement,
  tax and bank details, EU trader status, and Apple's Small Business
  Program. iOS and macOS share the bundle ID `nl.despaankamer.ccrlogger`,
  so one subscription group covers both (universal purchase).
- Terms of service for the subscription, and a privacy policy update
  naming RevenueCat and Paddle as processors of account data.
- Billing grace periods switched on in App Store Connect and the Play
  Console, about two weeks each (§1).
- RevenueCat: restore behaviour "keep with original App User ID"
  (§3), the webhook pointed at `https://api.anchorline.eu/v1/billing/webhook`
  with a shared secret, and Paddle connected for web purchase links.
  An older RevenueCat page calls the Paddle integration invite-only, so
  confirm that when the account is set up.
- The App Review account gets no grant, so the reviewer can make a
  sandbox purchase (§1).
- New secrets in the service's `.env` on the Hetzner box: the sync-pass
  signing key, RevenueCat's webhook secret and API key, a Resend API
  key, and an R2 API token limited to the attachments bucket (§4). They
  are never committed, and Sentry's scrubbing in the service covers
  them.
- PowerSync dashboard: add the service's JWKS URL at stage 2, and remove
  the Supabase JWT at stage 7.

## Costs introduced

Prices as checked on 2026-11-18. `docs/RELEASE_AND_MONETISATION.md`
("Costs") has the full estimate.

- RevenueCat: free up to $2,500 of tracked revenue per month, then 1% of
  all tracked revenue.
- Paddle: 5% + $0.50 per web sale. Paddle is merchant of record, so EU
  VAT is included.
- Store commission, charged on the price excluding VAT:
  - Apple: 15% under the Small Business Program. In the EU, under the
    terms from 2026-10-01, In-App Purchase is 26% outside the programme
    and still 15% within it.
  - Google Play: 15% on subscriptions (in the EEA, the UK and the US,
    split as a 10% service fee plus a 5% billing fee).
- Resend: within the free tier (3,000 emails a month).
- The service runs on the existing Hetzner box (€19.07 a month, shared
  with De Spaankamer), so it adds no hosting cost. The `pg_cron` sweep
  is free.
- The Worker gets no new routes; one extra Postgres call per signing
  doesn't change its cost.
