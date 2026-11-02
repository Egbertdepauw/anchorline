# Subscriptions and entitlements — design

Date: 2026-10-07
Status: design approved in conversation; awaiting spec review
Context: `docs/RELEASE_AND_MONETISATION.md` (goals, free/paid split,
channels, hosting, licence)

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
| What is paid? | Anchorline cloud sync, attachments, two-way Subsurface sync. Everything else is free, including one-way Subsurface import. |
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
- In-app account deletion. Apple requires it for apps with account
  creation, and the app has none today (`Settings → Reset everything`
  wipes data, not the account). It belongs to the store-release work.
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
- Sync is scoped per user by `infra/powersync-sync-rules.yaml`
  (`request.user_id()`), and every synced table has an
  `owner_full_access` row-level policy.
- Attachments go through the Cloudflare Worker (`worker/`), which
  verifies the Supabase JWT. Routes: `/sign-upload`, `/sign-download`,
  `/delete`. It has no tests, only `tsc --noEmit`.
- No purchase library and no entitlement table exist.

## Design

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
| `note` | Free text, used for grants |
| `created_at`, `updated_at` | |

Unique on (`user_id`, `source`).

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
| `updated_at` | |

**Rules**

- An account has access if at least one source is current: its state is
  `trial`, `active` or `payment_problem`, and its `access_until` is null
  or in the future.
- Only the server writes either table. The summary is recomputed by one
  SQL function whenever a source changes, and by an hourly sweep that
  ends anything past its date. A device's clock is never trusted.
- An account may read its own `account_access` row and nothing else.
  Both tables need explicit grants in their migration
  (`supabase/README.md`, issue #76).
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
| Payment problem | Yes, for the store's retry period | A renewal charge failed and is being retried |
| Granted | Yes | A grant from the owner |
| Ended | No | Cancelled and run out, refunded, or grant expired |

### 2. Enforcement

**Sync pass.** The app no longer hands PowerSync the Supabase session
token. It asks the Worker for a short-lived sync pass:

- New Worker route `POST /sync-token`: verifies the Supabase JWT, reads
  the account's `account_access` row, and if `has_access` is true returns
  a JWT signed with a key held by the Worker, valid for at most one hour.
  Otherwise it returns 403.
- The Worker publishes the matching public key as a JWKS document, and
  the PowerSync instance is configured to accept tokens signed by it.
- Without a pass a device cannot connect. An account whose access ends
  keeps its current connection until the pass expires, at most one hour.

**Why not the sync rules.** Making the sync rules return nothing for an
account without access would be simpler, but when a device's data leaves
its sync set, PowerSync removes that data from the device. That would
wipe a lapsed user's logbook. Refusing the connection leaves the local
database untouched. This behaviour is to be confirmed by experiment
before anything is built (stage 0).

**Database writes.** Every synced table's write policy additionally
requires access, through one SQL function `has_sync_access(user_id)`.
This is a second lock against a modified app. Reads stay as they are: an
account can still read its own rows over REST. That lets a lapsed user's
data be exported on request and exposes nothing that isn't theirs.

**The app.** `CloudSyncCoordinator` connects only when signed in and the
cached summary says the account has access. Without access the app
behaves as it does today when signed out: fully usable, with local
changes waiting in the upload queue.

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
account whose server copy was deleted, every dive, sample, annotation
and equipment record that was on the device is still on the device and
is back on the server. How the full re-upload is queued depends on the
stage 0 findings and is designed in stage 3's plan.

**Attachments.** The Worker checks `has_access` on `/sign-upload` and
`/sign-download`. `/delete` stays available so a user can always remove
their own files. With access ended: no uploads, and no downloads of
files not already on the device. Files already downloaded stay viewable.

**Subsurface.** One-way import is always available. Two-way sync checks
the cached summary before running. No server can enforce this; it is an
honour-system gate, accepted as such.

### 3. Buying

**Account first.** A subscription belongs to an Anchorline account. The
app requires sign-in before showing prices, and gives the account's id
to the subscription service as the customer id. That is what makes a
purchase valid across platforms.

**Where the offer appears.** In Settings → Account, and at the three
points where a free user reaches a paid feature: turning on sync, adding
an attachment, starting two-way Subsurface sync.

**The subscribe screen** shows both plans with prices fetched from the
channel (so they appear in the user's currency), the 30-day trial, a
"Restore purchases" button, and links to the terms and the privacy
policy.

| Platform | Flow |
|---|---|
| iOS, macOS, Android | The store's purchase sheet, through the `purchases_flutter` library. Then "Activating…" until the server has recorded the purchase, then sync starts |
| Windows, Linux | "Subscribe" opens a web purchase link in the browser, carrying the account id. The app refreshes when it regains focus or the user presses "I've paid" |

`purchases_flutter` supports Android, iOS and macOS, not Windows or
Linux. The Windows and Linux apps contain no purchase code; they only
read the summary.

**The purchase method follows how the app was distributed, not the
operating system.** Apple's in-app purchase works only in App Store
builds. A macOS copy distributed outside the Mac App Store (a later
Homebrew build, for example) buys through the web purchase link, like
Windows and Linux. The app knows its distribution channel through a
build-time setting, shared with the update check described in
`docs/superpowers/specs/2026-10-07-website-design.md`.

**After buying.** Settings → Account shows the plan, the next renewal
date and where it was bought. Changing plan or cancelling happens where
the purchase was made: the app links to the App Store or Play
subscription page, or to Paddle's customer page, and on other platforms
says where to manage it. If an account already has access from any
source, no second purchase is offered.

**Store rules.** The iOS and Android apps offer only in-app purchase and
do not mention or link to the web checkout.

**Trial limit.** The stores decide trial eligibility per store account.
The server records `trial_used`, and the web checkout then offers the
plan without a trial. This is best effort: someone could still take one
trial on a store and another elsewhere.

### 4. Server-side flows

**Purchase notifications.** New Worker route `POST /billing/webhook`
receives the subscription service's events (trial started, renewed,
payment problem, cancelled, expired, refunded, product changed). It
rejects any request without the shared secret, upserts the matching
`entitlement_sources` row, and recomputes the summary. Handling is
idempotent and tolerates duplicates and out-of-order arrival: an event
older than the row's last update is ignored.

**Refresh on demand.** New Worker route `POST /billing/refresh`,
authenticated as the user: asks the subscription service directly for
that account's status and corrects the record. Called by "Restore
purchases", by "I've paid", and after a store purchase completes. This
covers lost or late notifications.

**Grants.** Three SQL functions, executable only with the admin key,
run from the Supabase SQL editor or a script under `supabase/`:

- grant access to an email address, until a date or with no end, with a
  note;
- change or revoke a grant;
- list all grants.

**Hourly sweep.** A scheduled Worker run ends any source past its
`access_until` and recomputes affected summaries.

**Lapse schedule.** A daily scheduled Worker run, for accounts whose
`ended_at` is set:

| When | Action |
|---|---|
| Day 0 | Email: sync has stopped, the logbook stays on the devices, the server copy is kept until a stated date |
| 30 days before deletion | Reminder email |
| 7 days before deletion | Final reminder |
| 6 months after `ended_at` | Delete the account's rows in every synced table and its attachment files, increase `data_generation`, send a confirmation email |

- The account and its entitlement history are kept, so the person can
  sign in and resubscribe, and `trial_used` survives.
- Gaining access at any point clears `ended_at` and cancels the
  schedule.
- Each step records that it was done, so a run that fails halfway can be
  repeated safely. `data_generation` increases only after all rows and
  files are gone.
- Emails need a transactional email service. Supabase's built-in mail is
  for sign-in emails only. The service is chosen in stage 6's plan; the
  requirement is an HTTP API callable from a Worker and a free tier that
  covers a few hundred emails a month.

**Existing accounts at launch.** Before stage 7, every existing account
gets a grant: no end date for the owner's, and a period chosen per beta
tester.

### 5. Failure handling

| Problem | Handling |
|---|---|
| Notification lost or late | The service retries; `/billing/refresh` corrects on demand |
| Forged notification | Rejected without the shared secret |
| Refund or chargeback | Arrives as a notification; access ends at once |
| Worker unavailable | No new sync passes; syncing pauses for everyone within an hour. Local use is unaffected and changes queue. Accepted as the cost of server-side enforcement |
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
  write policies.
- **Worker** (it has no tests today; this work adds a test setup):
  `/sync-token` for accounts with and without access, attachment checks,
  webhook secret, duplicate and out-of-order events, refresh, the lapse
  schedule including a re-run after a simulated failure.
- **App**: the connect decision, the cached summary and its expiry, the
  subscribe screen per platform, hiding the offer when access exists,
  the two-way Subsurface gate.
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

| Stage | Adds | Enforced? |
|---|---|---|
| 0 | The PowerSync experiment | No |
| 1 | `entitlement_sources`, `account_access`, the grant functions, grants for all existing accounts, status shown in Settings | No |
| 2 | `/sync-token` and the app using it. PowerSync accepts both the Supabase token and the pass | No |
| 3 | `data_generation` and the re-upload protection | No |
| 4 | Store purchases on iOS, macOS and Android, the subscribe screen, `/billing/webhook`, `/billing/refresh` | No |
| 5 | Web purchase link and the Windows and Linux flow | No |
| 6 | Lapse emails and the 6-month deletion job | No |
| 7 | PowerSync accepts only the pass; the write-policy and Worker attachment checks become active | Yes |

App versions from before stage 2 stop syncing at stage 7. Beta testers
need notice and an update first.

## Set up outside the code

- Accounts with RevenueCat, Paddle, and an email service.
- Subscription products (monthly, yearly, 30-day trial) in App Store
  Connect and the Play Console, with each store's paid-apps agreement,
  tax and bank details.
- Terms of service for the subscription, and a privacy policy update
  naming the services that will handle account data.
- New Worker secrets: the Supabase admin key, the sync-pass signing key,
  the subscription service's webhook secret and API key, the email
  service's key.

## Costs introduced

- RevenueCat: free up to $2,500 of tracked revenue per month, then 1%
  (as published 2026-10-07).
- Paddle: a per-transaction fee on web sales; to be confirmed when the
  account is set up.
- Store cut: 15% under the small-business programmes.
- Cloudflare Workers scheduled runs and the extra routes fit the free
  plan at this scale.
