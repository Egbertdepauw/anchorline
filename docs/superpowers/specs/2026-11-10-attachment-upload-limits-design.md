# Per-account attachment upload limits: design

Date: 2026-11-10
Status: **approved by Egbert on 2026-11-10, as written.** It was
written without a Q&A round at his request. The "proposed" numbers and
decisions below, including §9, are confirmed. The per-account overrides
are still picked after the usage report (§7, step 2).
Issue: #196. Follows: issue #189 ("per-account upload limits on the Worker" was left
for later when email confirmation shipped in PR #190).
Related: `2026-10-07-subscriptions-entitlements-design.md`,
`2026-11-08-account-deletion-design.md`, and the standing backend
decision (one Dart service, Worker frozen).

## 1. Why

The app is publicly downloadable from anchorline.eu. Any account with a
confirmed email can store files in the R2 bucket, and nothing caps the
total. Attachments are meant to be paid, but entitlements aren't built
yet. Until they are, one account with a script can fill the bucket. That
costs money, and it makes the bucket free hosting for anything, including
content Egbert must never host.

Success means:

- One account can't store more than a set amount. That holds even with a
  modified app or direct API calls, and for every build already out
  there, including 44 to 47.
- An honest diver who hits the limit sees a plain message and knows what
  to do. They don't get a stuck "upload failed" row.
- Nobody loses a file they already have.
- When entitlements arrive, the limit becomes part of the paid offer
  without being redesigned.

## 2. What the code does today

Read on 2026-11-10:

1. **The app signs and uploads before Postgres sees anything.**
   `DiveAttachmentsNotifier.addFile` inserts a local `pending` row, and
   `AttachmentUploaderImpl.upload` calls the Worker's `/sign-upload`,
   then PUTs the bytes straight to R2. The `dive_attachments` row reaches
   Postgres later, through PowerSync. Someone calling the Worker directly
   never needs to write a row at all.
2. **The 25 MB cap is self-declared.** `/sign-upload` checks the
   `size_bytes` the caller *claims*. `presignUpload` (`worker/src/r2.ts`)
   signs with aws4fetch, and aws4fetch leaves `content-type` and
   `content-length` out of the signature by default (its
   `UNSIGNABLE_HEADERS`; `allHeaders` isn't set). So one signed URL
   accepts any size up to R2's 5 GB single-PUT maximum, with any
   Content-Type. The comment in `r2.ts` saying Content-Type is signed is
   wrong. The MIME allowlist is bypassable the same way, so a caller can
   store `text/html` and serve it back through a presigned GET.
3. **Deleting an attachment doesn't delete the file.**
   `softDelete` sets `deleted_at` (with a 5-second UNDO snackbar).
   Nothing ever calls the Worker's `/delete` for a single attachment. The
   only callers are Reset Everything (`AttachmentObjectWiper`) and
   account deletion. So every deleted attachment and every attachment
   under a deleted dive is still in R2.
4. **Retries can leave orphans.** Every `/sign-upload` call mints a
   fresh UUID key. If the PUT succeeded but `markUploaded` failed, the
   retry uploads the bytes again under a new key and the first object is
   orphaned. That's rare and small.
5. The Worker never touches Postgres. It verifies the Supabase JWT and
   uses the `sub` claim as the key prefix: `attachments/{owner_id}/...`.
   It has an R2 binding (`env.BUCKET`) that can list by prefix.

Point 1 rules out a Postgres-only limit as real protection. Point 2 means
any limit is worthless until uploads are bound to their declared size.
Point 3 means a limit measured on R2 would never go down when users
delete things, unless the app starts deleting the files.

## 3. Options

| | Option | Stops a scripted caller? | Covers builds 44–47? | Cost | Verdict |
|---|---|---|---|---|---|
| A | **Postgres quota**: a trigger or RLS check on `dive_attachments` insert that sums `size_bytes` per `owner_id` | No. Bytes are in R2 before the row arrives, and a script skips the row | Partly: honest builds only | ~½ day, one migration | Not recommended. It also turns an honest refusal into a row the PowerSync connector quarantines as a poison op: the attachment shows locally and never syncs. It counts sizes the client claims |
| B | **Worker exception**: `/sign-upload` signs the size and type into the URL, measures the account's real R2 usage by listing its prefix, and refuses past the limit | Yes | Yes, from the moment it's deployed | ~1–2 days Worker, ~1–2 days app | **Recommended** |
| C | **Wait for the Dart service** | Not until the service exists *and* takes over signing | No. Old builds have the Worker URL baked in, so the Worker would have to change or shut down anyway | Zero now, unbounded exposure meanwhile | Not viable while the app is public |
| D | **Worker reads Postgres** (sums `size_bytes` over the user's rows with a service key) | Partly. It trusts client-claimed sizes and misses files with no row | Yes | B's cost plus a service-role secret in the Worker | Worse than B on every axis |

Zero-code backstops, worth doing whichever option is picked:

- A Cloudflare billing or usage notification on R2 storage, so a
  many-account attack shows up in Egbert's inbox.
- A kill switch: a Worker variable that refuses all new uploads (§5.5).

**Decision (proposed): B, recorded as the second exception to the
Worker freeze**, next to account deletion running as a Postgres
function. Why: it's the only option that protects the builds already in
the wild. It's small and bounded: no new route except an optional
`/usage`, no new secrets, no Postgres access. The logic (list a prefix,
sum, compare) ports straight to Dart when the service takes over
signing, because ListObjectsV2 is the same S3 call there.

**Freeze boundary.** The exception covers exactly §5. Entitlement checks
(`has_access`) are *not* part of it. They stay in the entitlements spec,
and they get built wherever signing lives when entitlements ship.

## 4. The limit

**Measured on:** the objects actually in R2 under
`attachments/{owner_id}/`, as listed by the Worker's R2 binding. Not
client-claimed sizes and not Postgres rows. Orphans and not-yet-purged
deleted files count, which is why §6.2 makes deletes free space.

**Both bytes and file count.** Bytes is what costs money. File count
bounds the per-request listing cost (one list call per 1,000 objects)
and R2 operation counts (millions of tiny files).

**Proposed numbers:**

| Phase | Who | Bytes | Files |
|---|---|---|---|
| Now, until entitlements are enforced | Every confirmed account | **1 GB** | **1,000** |
| Now | Named accounts (Egbert, beta testers) via override | as set per account | as set |
| After entitlements | Account with access | **10 GB** | **10,000** |
| After entitlements | Account without access | 0: uploads refused by the entitlement check, not by this limit | — |

Why these numbers: the MIME allowlist has no video. A phone photo is
2–5 MB, so 1 GB is roughly 250–500 photos, plenty for trying the feature.
10 GB at R2's $0.015/GB-month is $0.15/month per account at the very
worst, small against any subscription price. The 10 GB tier isn't
enforced until entitlements exist, so it can change with real usage data.
Storage tiers stay out of scope, as in the entitlements spec.

**Configuration**, as Worker variables in `wrangler.toml` `[vars]`:

- `QUOTA_BYTES`, `QUOTA_FILES`: the default limit.
- `QUOTA_OVERRIDES`: JSON `{ "<user uuid>": { "bytes": n, "files": n } }`.
  Changing it needs a deploy or a dashboard edit. That's fine for a
  handful of accounts. When entitlements land, overrides move into
  `account_access` (or the Dart service) and this variable goes away.
- `UPLOADS_ENABLED`: `"true"` / `"false"` (§5.5).

**Existing accounts over the limit:** nothing is deleted, ever. They keep
every file and can still view, download and delete. New uploads are
refused until they're under the limit, unless they have an override.
Before the limit is switched on, Egbert runs a one-off per-account usage
report (§7, step 2) and gives overrides to beta accounts that need them.

## 5. Worker changes (`worker/`)

### 5.1 Bind the declared size and type into the signed URL

`presignUpload` takes `sizeBytes` and signs the PUT with both
`Content-Type` and `Content-Length` (aws4fetch `allHeaders: true`, or an
explicit equivalent). R2 then refuses a PUT whose body length or type
doesn't match. Builds 44–47 already send a `Content-Type` equal to the
signed MIME and a `Content-Length` equal to `size_bytes`
(`_putBytes` sets `contentLength = bytes.length`, and the same
`bytes.length` goes to `/sign-upload`). So nothing breaks.

**Must be verified against real R2 before deploying:** a PUT with a
different length, and one with a different Content-Type, each get 403.
If R2 turns out not to enforce a signed `Content-Length`, stop and come
back. The fallback is R2's `x-amz-content-sha256` or a POST policy, and
that changes the app.

Fix the misleading comment in `r2.ts`.

### 5.2 Quota check on `/sign-upload`

After JWT and body validation:

1. Resolve the account's limit: the override, else the default.
2. List `attachments/{sub}/` via `env.BUCKET.list({ prefix, cursor })`,
   paging until done. Sum `size` and count objects.
3. If `used_bytes + size_bytes > limit_bytes` or
   `used_files + 1 > limit_files`, return **413**:

   ```json
   { "error": "quota_exceeded",
     "used_bytes": 0, "limit_bytes": 0,
     "used_files": 0, "limit_files": 0 }
   ```

4. Otherwise sign as today, and add the same four usage fields to the
   success response, *before* this upload. Old builds ignore extra
   fields.

Listing cost: one R2 list call (class A) per 1,000 objects per sign.
Under the 1,000-file limit, that's one call per upload.

### 5.3 Burst limit

The listing only sees files that have landed. Signed URLs live for
5 minutes, so a script could collect many URLs before uploading any.
Add a per-account rate limit on `/sign-upload` with the Workers Rate
Limiting binding, keyed on `sub`. Proposed: **20 per 60 s**. A refusal
returns **429** `{ "error": "rate_limited" }`.

Worst-case overrun beyond the limit is then about 5 min × 20 ×
25 MB ≈ 2.5 GB, once per account. That's accepted. A Durable Object
holding live reservations would be exact, but it's more Worker under a
freeze, and the real many-account problem is solved by the paid gate,
not here.

The builder confirms the Rate Limiting binding is available on the
account's Workers plan. If it isn't, ship without §5.3 and say so. The
overrun bound then becomes "unbounded within 5 minutes", which needs
Egbert's call.

### 5.4 `POST /usage` (optional; drop it to keep the exception smaller)

Same auth. It returns the four usage fields plus `uploads_enabled`. The
Settings screen uses it so usage is right on every device, even before
the first upload. Without it, the app only learns usage from a
`/sign-upload` response.

### 5.5 Kill switch

If `UPLOADS_ENABLED` isn't `"true"`, `/sign-upload` returns **503**
`{ "error": "uploads_disabled" }`. Downloads and deletes are untouched.

### 5.6 Unchanged

`/sign-download` and `/delete` don't change. Deleting must always work,
so a user can always get back under the limit.

### 5.7 Tests

`vitest` is already set up (`keepalive.test.ts`). Add unit tests for:
limit resolution (default vs override vs malformed JSON, which falls
back to the default and logs), the quota decision at the exact
boundaries, multi-page listing, the 413/429/503 bodies, and the signed
URL carrying `content-length` and `content-type` in
`X-Amz-SignedHeaders`. Then do the manual R2 check from §5.1.

## 6. App changes

### 6.1 Refusals the user can act on

`AttachmentSigner` maps 413 `quota_exceeded`, 429 `rate_limited` and
503 `uploads_disabled` to typed exceptions carrying the usage fields.

- **Quota refused while adding a file:** the attachment isn't added (the
  pending row is soft-deleted and its pending-upload entry cleared, so
  nothing is stuck and nothing retries). A dialog says:

  > **Attachment storage full**
  > 0.98 GB of 1 GB used (412 of 1,000 files). This file needs 4.2 MB.
  > Delete attachments you no longer need to make room.
  > [Free space now] [OK]

  **Free space now** runs the purge from §6.2 immediately, for every
  soft-deleted attachment, then retries the add once. It only appears
  when there's something to purge.
- **Quota refused on a manual retry** (the retry button on a `failed`
  row; there's no automatic retry sweep today, despite the comment in
  migration 0004): the row stays `failed`, and the same dialog appears.
- **Rate limited:** the upload waits and retries by itself; no dialog.
  It's only reached with very large batches.
- **Uploads disabled:** "Uploads are paused right now. Your existing
  attachments are fine." The row stays `failed`, and the user can retry
  later.

Builds 44–47 show their existing generic failure on all of these. That's
accepted.

### 6.2 Deletes free space

A soft-deleted file attachment has its R2 object deleted through
`/delete` once it has been deleted for **24 hours** (proposed). That's
well past the 5-second UNDO and covers an undone dive delete the next
morning. Mechanism: a new sweep on app start and foreground, while
signed in. Any device may run it; `/delete` is idempotent.

After the purge, the row records that its file is gone. Proposal: a new
`upload_state` value **3 = purged**; the Postgres column has no CHECK on
its values. Restore is no longer offered for that row. The first run on
a new build also purges every attachment deleted before this feature
existed, so existing accounts get their space back.

Orphans without any row (§2 point 4, and direct-caller uploads) aren't
touched by the app. They count against the limit, which punishes only
the caller who created them. Egbert can clear them with the override or
by hand. A proper bucket-vs-table orphan sweep stays with the Dart
service, as already noted in the account-deletion work.

### 6.3 Showing usage

Settings → Account gets one line under the sync section:
"Attachments: 0.4 GB of 1 GB · 120 of 1,000 files", from `/usage` (or
the last `/sign-upload` response cached locally, if §5.4 is dropped).
That's server state, not user data, so it isn't synced, like
`account_access` in the entitlements spec.

## 7. Rollout

1. **Worker §5.1** (bind size and type), deployed alone and checked
   against real R2. It closes the bypass for every build. Ideally this
   lands before the repo goes public, because the hole is readable in
   `r2.ts`.
2. **Usage report**: a one-off script (wrangler or the S3 API with the
   existing R2 token) that lists per-account bytes and files. Egbert
   picks the overrides. The output stays out of git, because it contains
   user ids.
3. **Worker §5.2–5.5**, with the limit on. Set up the Cloudflare
   billing or usage notification at the same time.
4. **App §6**, in the next release. The purge sweep is what makes the
   limit livable, so this follows step 3 closely.
5. Record the freeze exception in the backend-decision memory and in
   `worker/README.md`.

## 8. Out of scope

- Entitlement checks (`has_access`) on signing: entitlements spec.
- Storage tiers, buying more space.
- Limits on downloads. Presigned GETs are owner-only and R2 egress is
  free. Revisit if `/sign-download` call volume ever looks abusive.
- Many-account abuse (one person, many disposable emails). The real fix
  is attachments being paid. Until then, the backstops in §3 and a
  modest default limit bound it.
- The bucket-wide orphan sweep (Dart service).

## 9. For Egbert to confirm

1. Option B and the freeze exception, scoped as in §3.
2. The numbers: 1 GB / 1,000 files now, 10 GB / 10,000 files with access
   later, 20 signs per minute.
3. Whether `/usage` (§5.4) is in, or the exception stays smaller.
4. The 24-hour purge delay and the `upload_state = 3` marker.
5. Which accounts get overrides, after the usage report.
