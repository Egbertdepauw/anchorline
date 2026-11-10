# Per-account attachment upload limits Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cap each account's R2 attachment storage, measured on what is
actually in R2, and give honest users a way to see and recover space.

**Architecture:** The Cloudflare Worker's `/sign-upload` binds the
declared size and type into the presigned PUT, lists the caller's
`attachments/{sub}/` prefix, and refuses past the limit. The Flutter app
maps the refusals to a "storage full" dialog, purges R2 objects of
attachments soft-deleted more than 24 hours ago, and shows usage in
Settings.

**Tech Stack:** TypeScript Worker (aws4fetch, vitest, wrangler), Flutter
/ Dart (package:http, PowerSync, flutter_test).

**Spec:** `docs/superpowers/specs/2026-11-10-attachment-upload-limits-design.md`
(approved 2026-11-10). Issue #196.

## Global Constraints

- The Worker change is a bounded exception to the Worker freeze: only
  what the spec's §5 lists. No entitlement (`has_access`) checks, no
  Postgres access, no new secrets.
- Default limit: `QUOTA_BYTES = "1000000000"` (decimal 1 GB),
  `QUOTA_FILES = "1000"`. The 10 GB / 10,000 tier isn't configured in
  this plan; it arrives with entitlements.
- Rate limit: 20 `/sign-upload` calls per 60 s per account (`sub`).
- Error bodies, exactly: 413 `{"error":"quota_exceeded","used_bytes":n,"limit_bytes":n,"used_files":n,"limit_files":n}`,
  429 `{"error":"rate_limited"}`, 503 `{"error":"uploads_disabled"}`.
- Usage fields on the success response and `/usage` describe usage
  *before* the upload being signed.
- Nothing already stored is ever deleted by the limit. `/sign-download`
  and `/delete` don't change.
- Purge delay: 24 hours after `deleted_at`. Purged rows get
  `upload_state = 3`.
- Builds 44–47 must keep uploading normally below the limit.
- Everything in git is English. Don't run `dart format` on whole files
  (main isn't format-clean; match the surrounding style by hand).
- Deploying the Worker is a production change: it needs Egbert's
  go-ahead each time (Tasks 1 and 4).
- Copy, exactly:
  - Dialog title: `Attachment storage full`
  - Dialog body: `{used} of {limit} used ({usedFiles} of {limitFiles} files). This file needs {size}. Delete attachments you no longer need to make room.`
  - Buttons: `Free space now` (only when something is purgeable), `OK`
  - Uploads paused: `Uploads are paused right now. Your existing attachments are fine.`
  - Failed-row label on a quota refusal: `Storage full`
  - Settings row title `Attachments`, value `{used} of {limit} · {usedFiles} of {limitFiles} files`

## Out of scope (follow-ups to note on #196, not to build)

- Deleting a dive doesn't soft-delete its attachments (`DiveDao.softDeleteDive`
  never touches `dive_attachments`), so those files keep counting. Open a
  separate issue for that.
- The bucket-wide orphan sweep (Dart service).

## Review Focus

1. **R2 doesn't enforce a signed `Content-Length`.** Expected: Task 1's
   manual check catches it before anything else ships, and work stops.
   Pinned by Task 1, Step 6.
2. **Old builds (44–47) break on the new signature,** for example a client
   stack that sends `Transfer-Encoding: chunked` instead of `Content-Length`.
   Expected: a build-46 upload still succeeds after Task 1 deploys. Pinned
   by Task 1, Step 6 (an upload from an installed release build).
3. **A malformed `QUOTA_OVERRIDES`** (bad JSON, negative or string
   numbers). Expected: the Worker falls back to the default limit, logs,
   and keeps serving. Pinned by Task 3 tests.
4. **The purge sweep running for a row with no real object** (the
   `pending:<id>` sentinel key of a never-uploaded file). Expected: the row
   is marked purged without calling `/delete`. Pinned by Task 6 tests.
5. **"Free space now" with nothing purgeable, or retrying the add still
   over the limit.** Expected: the button is hidden when nothing is
   purgeable, and a second refusal shows the dialog again without a loop.
   Pinned by Task 7 tests.

---

### Task 1: Bind the declared size and type into the presigned PUT

**Files:**
- Modify: `worker/src/r2.ts` (`presignUpload`, `PresignUploadParams`, the
  misleading Content-Type comment)
- Modify: `worker/src/index.ts` (`handleSignUpload` passes `sizeBytes`)
- Create: `worker/src/r2.test.ts`

**Interfaces:**
- Produces: `PresignUploadParams` gains `sizeBytes: number`.
  `presignUpload` signs `content-type` and `content-length`.

- [ ] **Step 1: Write the failing test** `worker/src/r2.test.ts`

```ts
describe("presignUpload", () => {
  it("signs content-length and content-type into the URL", async () => {
    const { url } = await presignUpload({
      accountId: "acc", bucket: "b", accessKeyId: "k", secretAccessKey: "s",
      key: "attachments/u/d/x.pdf", mimeType: "application/pdf", sizeBytes: 1234,
    });
    const signed = new URL(url).searchParams.get("X-Amz-SignedHeaders")!.split(";");
    expect(signed).toContain("content-length");
    expect(signed).toContain("content-type");
    expect(signed).toContain("host");
  });
});
```

- [ ] **Step 2: Run it and see it fail**

Run: `cd worker && npx vitest run src/r2.test.ts`
Expected: FAIL. The signed headers are only `host`.

- [ ] **Step 3: Implement it.** Sign the PUT with headers `Content-Type:
  mimeType` and `Content-Length: String(sizeBytes)`, passing
  `allHeaders: true` in the `aws` options. Rewrite the doc comment to say
  both headers are signed and why. In `handleSignUpload`, pass
  `sizeBytes: parsed.sizeBytes`.

- [ ] **Step 4: Run the tests and typecheck**

Run: `cd worker && npx vitest run && npm run typecheck`
Expected: all pass, no type errors.

- [ ] **Step 5: Commit**

```bash
git add worker/src/r2.ts worker/src/r2.test.ts worker/src/index.ts
git commit -m "fix(worker): bind size and type into presigned uploads (#196)"
```

- [ ] **Step 6: Verify against real R2 (needs Egbert's go-ahead to deploy)**

After `cd worker && npx wrangler deploy`, with a real access token
(`TOKEN`) and the Worker URL (`WORKER`), sign one upload with
`size_bytes: 11` and `mime_type: text/plain`, then PUT three times:

1. `curl -X PUT -H 'Content-Type: text/plain' --data-binary 'hello world' "$URL"` → **200**
2. Same URL with a fresh signature, body `hello world!!` (13 bytes) → **403**
3. Fresh signature, body `hello world` but `Content-Type: text/html` → **403**

Then attach a photo from an installed release build 46 or 47, and check
that it uploads. If case 2 returns 200, **stop**: revert the deploy
(`npx wrangler rollback`) and report back. The spec's fallback changes
the app and needs Egbert.

### Task 2: Per-account usage report

**Files:**
- Create: `worker/scripts/usage-report.mjs`
- Modify: `.gitignore` (add `worker/usage-report*.csv`)

**Interfaces:**
- Produces: a CSV on stdout: `owner_id,bytes,files`, sorted by bytes
  descending. Run with `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`,
  `R2_SECRET_ACCESS_KEY` and `R2_BUCKET_NAME` set in the environment.

- [ ] **Step 1: Implement it.** Use `aws4fetch`'s `AwsClient` (already a
  dependency) to page `ListObjectsV2` (`list-type=2&prefix=attachments/&continuation-token=…`)
  against `https://{account}.r2.cloudflarestorage.com/{bucket}`. Parse
  `<Key>` and `<Size>` from the XML with regexes (no new dependency).
  Group by the second path segment. Never print credentials.
- [ ] **Step 2: Run it** (Egbert supplies the R2 credentials in his shell):
  `node worker/scripts/usage-report.mjs > worker/usage-report.csv`.
  Expected: one line per account, and the totals match the bucket size in
  the Cloudflare dashboard.
- [ ] **Step 3: Egbert picks the overrides** from the report (any account
  near or above 1 GB / 1,000 files). Record them as the
  `QUOTA_OVERRIDES` JSON for Task 4. Don't commit the CSV.
- [ ] **Step 4: Commit the script**

```bash
git add worker/scripts/usage-report.mjs .gitignore
git commit -m "chore(worker): per-account attachment usage report (#196)"
```

### Task 3: Quota module

**Files:**
- Create: `worker/src/quota.ts`
- Create: `worker/src/quota.test.ts`
- Modify: `worker/src/types.ts`

**Interfaces:**
- Produces (in `types.ts`): `Env` gains `QUOTA_BYTES: string`,
  `QUOTA_FILES: string`, `QUOTA_OVERRIDES?: string`,
  `UPLOADS_ENABLED: string`, `SIGN_UPLOAD_LIMITER: RateLimit` (the Workers
  Rate Limiting binding type; declare a local
  `interface RateLimit { limit(o: { key: string }): Promise<{ success: boolean }> }`
  if `@cloudflare/workers-types` lacks it). Also
  `interface Usage { used_bytes: number; limit_bytes: number; used_files: number; limit_files: number }`,
  and `SignUploadResponse` extends `Usage`.
- Produces (in `quota.ts`):
  - `resolveLimit(env: Pick<Env,"QUOTA_BYTES"|"QUOTA_FILES"|"QUOTA_OVERRIDES">, sub: string): { bytes: number; files: number }`
  - `measureUsage(bucket: Pick<R2Bucket,"list">, sub: string): Promise<{ bytes: number; files: number }>`
    (pages `list({ prefix: \`attachments/${sub}/\`, cursor })` until `truncated` is false)
  - `usageFor(env, sub): Promise<Usage>`
  - `wouldExceed(u: Usage, sizeBytes: number): boolean`:
    `used_bytes + sizeBytes > limit_bytes || used_files + 1 > limit_files`

- [ ] **Step 1: Write the failing tests** in `quota.test.ts`, with a fake
  bucket whose `list` returns preset pages:

```ts
it("uses the default when there is no override", () =>
  expect(resolveLimit({ QUOTA_BYTES: "1000000000", QUOTA_FILES: "1000" }, "u1"))
    .toEqual({ bytes: 1_000_000_000, files: 1000 }));
it("uses a per-account override", () =>
  expect(resolveLimit({ QUOTA_BYTES: "1000000000", QUOTA_FILES: "1000",
    QUOTA_OVERRIDES: '{"u1":{"bytes":5000000000,"files":5000}}' }, "u1"))
    .toEqual({ bytes: 5_000_000_000, files: 5000 }));
it("falls back to the default and logs on malformed overrides", ...);   // "{not json", '{"u1":{"bytes":-1}}', '{"u1":{"bytes":"5"}}'
it("sums sizes across pages", ...);          // 2 pages, 1000 + 3 objects → files 1003, bytes = sum
it("lists only the caller's prefix", ...);   // assert list was called with prefix "attachments/u1/"
it("refuses one byte over the byte limit and allows exactly at it", () => {
  const u = { used_bytes: 900, limit_bytes: 1000, used_files: 1, limit_files: 10 };
  expect(wouldExceed(u, 100)).toBe(false);
  expect(wouldExceed(u, 101)).toBe(true);
});
it("refuses the file that would exceed the file limit", () =>
  expect(wouldExceed({ used_bytes: 0, limit_bytes: 1000, used_files: 10, limit_files: 10 }, 1)).toBe(true));
```

- [ ] **Step 2: Run them and see them fail**

Run: `cd worker && npx vitest run src/quota.test.ts`
Expected: FAIL. The module doesn't exist.

- [ ] **Step 3: Implement `quota.ts` and the `types.ts` additions.** An
  override entry is valid only if both `bytes` and `files` are
  non-negative integers. Otherwise use the default for that account and
  `console.warn` once per request.
- [ ] **Step 4: Run all Worker tests and typecheck**

Run: `cd worker && npx vitest run && npm run typecheck`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add worker/src/quota.ts worker/src/quota.test.ts worker/src/types.ts
git commit -m "feat(worker): per-account attachment quota module (#196)"
```

### Task 4: Enforce the quota, rate limit and kill switch on the routes

**Files:**
- Create: `worker/src/upload_gate.ts`, `worker/src/upload_gate.test.ts`
- Modify: `worker/src/index.ts` (`handleSignUpload`, new `/usage` case and `handleUsage`)
- Modify: `worker/wrangler.toml` (`[vars]` and the rate-limit binding)
- Modify: `worker/README.md` (routes table, error codes, config, freeze-exception note)

**Interfaces:**
- Consumes: `usageFor`, `wouldExceed` (Task 3).
- Produces: `gateSignUpload(env: Env, sub: string, sizeBytes: number): Promise<{ ok: true; usage: Usage } | { ok: false; response: Response }>`.
  It runs in this order: kill switch (503), rate limit (429), quota (413).
  `POST /usage` returns `Usage & { uploads_enabled: boolean }`.

- [ ] **Step 1: Write the failing tests** in `upload_gate.test.ts`, with a
  fake env (fake bucket, fake limiter):
  - `UPLOADS_ENABLED: "false"` → 503 `{ error: "uploads_disabled" }`, and the limiter isn't called.
  - The limiter returns `{ success: false }` → 429 `{ error: "rate_limited" }`, and the bucket isn't listed.
  - The limiter is called with `{ key: sub }`.
  - Usage 999,999,990 bytes, `sizeBytes` 11 → 413 with exactly the five fields from Global Constraints.
  - Under the limit → `{ ok: true, usage }`, where usage excludes the new file.
  - `UPLOADS_ENABLED` missing or `"TRUE"` → treated as disabled (only the exact string `"true"` enables).
- [ ] **Step 2: Run them and see them fail**

Run: `cd worker && npx vitest run src/upload_gate.test.ts`
Expected: FAIL.

- [ ] **Step 3: Implement `upload_gate.ts`,** then wire it in.
  `handleSignUpload` calls `gateSignUpload` after body validation and
  before building the key, and spreads `usage` into the success payload.
  Add `case "/usage"` to `dispatch`: authenticate, then
  `Response.json({ ...await usageFor(env, sub), uploads_enabled: env.UPLOADS_ENABLED === "true" })`.
- [ ] **Step 4: Configure `wrangler.toml`.** Add `QUOTA_BYTES = "1000000000"`,
  `QUOTA_FILES = "1000"`, `UPLOADS_ENABLED = "true"` and the
  `QUOTA_OVERRIDES` JSON from Task 2 under `[vars]`. Add the rate-limit
  binding named `SIGN_UPLOAD_LIMITER` with limit 20 and period 60. Check
  the binding syntax for the installed wrangler version
  (`npx wrangler --version`; `[[unsafe.bindings]] type = "ratelimit"` on
  v3, `[[ratelimits]]` on v4). If the account's plan doesn't offer the
  binding, leave the limiter out of `gateSignUpload` and report it to
  Egbert (spec §5.3); don't silently drop it.
- [ ] **Step 5: Update `worker/README.md`:** routes table (`/usage`), the
  new error codes, the four variables, and one paragraph: "Second
  exception to the Worker freeze (2026-11-10, #196): upload limits only.
  Moves to the Dart service when it takes over signing."
- [ ] **Step 6: Run the tests and a dry run**

Run: `cd worker && npx vitest run && npm run typecheck && npx wrangler deploy --dry-run`
Expected: all pass; the dry run lists the bindings, including the rate limiter.

- [ ] **Step 7: Commit**

```bash
git add worker/
git commit -m "feat(worker): enforce per-account upload quota (#196)"
```

- [ ] **Step 8: Deploy and smoke test (needs Egbert's go-ahead).** Deploy.
  Call `/usage` with a real token and expect the account's figures. Then
  temporarily set that account's override to `{"bytes":1,"files":1}`,
  deploy, sign an upload and expect 413. Restore the override and deploy
  again. Also ask Egbert to set up a Cloudflare billing or usage
  notification for R2 storage (dashboard only).

### Task 5: App signer — usage and typed refusals

**Files:**
- Modify: `lib/sync/attachments/attachment_signer.dart`
- Test: `test/sync/attachments/attachment_signer_test.dart`

**Interfaces:**
- Produces:
  - `class AttachmentUsage { final int usedBytes, limitBytes, usedFiles, limitFiles; final bool? uploadsEnabled; }`
    with `static AttachmentUsage? tryParse(Map<String, dynamic> json)`.
    It returns null when any of the four ints is missing, so old Worker
    responses still parse.
  - `SignUploadResponse` gains `final AttachmentUsage? usage`.
  - `class AttachmentQuotaExceededException implements Exception { final AttachmentUsage usage; }`
    for a 413 with `error == "quota_exceeded"`.
  - `class AttachmentRateLimitedException implements Exception` for a 429.
  - `class AttachmentUploadsDisabledException implements Exception` for a 503 with `error == "uploads_disabled"`.
  - `Future<AttachmentUsage> fetchUsage()` → `POST /usage` with `{}`.
  - Any other non-2xx is still a `SignerException`.

- [ ] **Step 1: Write the failing tests** (MockClient, same style as the
  existing file): a 413 body → `AttachmentQuotaExceededException` with
  `usage.usedBytes == 999999990`; a 429 → `AttachmentRateLimitedException`;
  a 503 `uploads_disabled` → `AttachmentUploadsDisabledException`; a 503
  with another body → `SignerException`; a success with usage fields →
  `response.usage!.limitFiles == 1000`; a success without them →
  `usage == null`; `fetchUsage` posts to `/usage` and parses
  `uploads_enabled`.
- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/sync/attachments/attachment_signer_test.dart`
Expected: FAIL. The new types aren't defined.

- [ ] **Step 3: Implement it.** Decode the error body inside `_post`
  before the generic `SignerException`.
- [ ] **Step 4: Run the tests**

Run: `flutter test test/sync/attachments/attachment_signer_test.dart && flutter analyze lib/sync/attachments`
Expected: PASS, no issues.

- [ ] **Step 5: Commit**

```bash
git add lib/sync/attachments/attachment_signer.dart test/sync/attachments/attachment_signer_test.dart
git commit -m "feat(attachments): typed quota and rate-limit refusals in signer (#196)"
```

### Task 6: Purge R2 objects of deleted attachments

**Files:**
- Modify: `lib/data/models/dive_attachment.dart` (`UploadState.purged(3)`)
- Modify: `lib/data/db/dive_attachments_dao.dart` (`listPurgeable`,
  `markPurged`, `restore` guard, `softDelete` doc comment)
- Create: `lib/sync/attachments/attachment_purger.dart`
- Modify: `lib/ui/app_shell.dart` (construct it; run it on start when
  signed in, on sign-in, and on `AppLifecycleState.resumed`)
- Test: `test/data/db/dive_attachments_dao_test.dart`,
  `test/sync/attachments/attachment_purger_test.dart`

**Interfaces:**
- Produces:
  - `Future<List<FileAttachment>> listPurgeable(DateTime deletedBefore)`:
    `kind = 'file' AND deleted_at IS NOT NULL AND deleted_at < ? AND upload_state != 3`.
  - `Future<void> markPurged(String id)`: sets `upload_state = 3`, bumps
    `version` and `updated_at`, stamps `owner_id` (same pattern as
    `markUploadFailed`).
  - `restore(id)` is a no-op for a row with `upload_state = 3`.
  - `class AttachmentPurger { AttachmentPurger({required DiveAttachmentsDao dao, required Future<void> Function(String objectKey) deleteObject, DateTime Function()? now}); Future<int> purgeDeleted({Duration minAge = const Duration(hours: 24)}); Future<bool> hasPurgeable(); }`.
    `purgeDeleted` returns the number of rows marked purged. A row whose
    `storageKey` starts with `pending:` is marked purged without calling
    `deleteObject`. A `deleteObject` failure leaves the row unpurged and
    continues with the next row. Concurrent calls share one in-flight run.

- [ ] **Step 1: Write the failing tests**
  - DAO: a row deleted 25 h ago is listed for a 24 h cutoff; deleted 23 h
    ago, it isn't. Already purged → not listed. A live row → not listed.
    A link row → not listed. `markPurged` sets state 3 and bumps the
    version. `restore` on a purged row leaves `deleted_at` set.
  - Purger: deletes the real key and marks it purged. The `pending:` key
    gets no delete call and is still marked purged. A throwing delete
    leaves that row unpurged, and the others are still purged. Two
    overlapping `purgeDeleted` calls → `deleteObject` called once per key.
    `minAge: Duration.zero` includes a row deleted a second ago.
    `hasPurgeable()` uses a zero cutoff.
  - `UploadState.fromWire(3) == UploadState.purged`.
- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/data/db/dive_attachments_dao_test.dart test/sync/attachments/attachment_purger_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement it and wire it into `app_shell.dart`.**
  Fire-and-forget, errors logged with `debugPrint`, and only when
  `Supabase.instance.client.auth.currentSession != null`. The deleter is
  `(k) => _attachmentSigner.deleteObject(objectKey: k)`. Pass the purger
  into `DiveAttachmentsNotifier` for Task 7. Note: builds 44–47 read state
  3 as `pending` (`fromWire` fallback). That's harmless because purged
  rows are always soft-deleted and every list query filters
  `deleted_at IS NULL`.
- [ ] **Step 4: Run the tests and analyze**

Run: `flutter test && flutter analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data lib/sync/attachments lib/ui/app_shell.dart test/data/db test/sync/attachments
git commit -m "feat(attachments): purge R2 objects of deleted attachments after 24h (#196)"
```

### Task 7: Storage-full handling in the uploader, notifier and UI

**Files:**
- Modify: `lib/sync/attachments/attachment_uploader.dart` (interface: `discard`)
- Modify: `lib/sync/attachments/attachment_uploader_impl.dart`
- Modify: `lib/ui/notifiers/dive_attachments_notifier.dart`
- Create: `lib/ui/widgets/storage_full_dialog.dart`
- Create: `lib/ui/format/attachment_usage_format.dart`
- Modify: `lib/ui/widgets/dive_attachments_section.dart`, `lib/ui/widgets/dive_media_tab.dart`
- Test: `test/sync/attachments/attachment_uploader_impl_test.dart`,
  `test/ui/notifiers/dive_attachments_notifier_test.dart`,
  `test/ui/widgets/storage_full_dialog_test.dart`,
  `test/ui/format/attachment_usage_format_test.dart`

**Interfaces:**
- Consumes: the Task 5 exceptions and `AttachmentUsage`;
  `AttachmentPurger.hasPurgeable()` / `purgeDeleted(minAge: Duration.zero)` (Task 6).
- Produces:
  - `AttachmentUploader.discard(String attachmentId)` clears the
    pending-upload entry.
  - On `AttachmentRateLimitedException`, the uploader waits and re-signs:
    up to 3 tries, 15 s apart (delay injectable for tests). After that it
    fails as usual.
  - The `UploadFailedException.cause` keeps the typed exception.
  - `DiveAttachmentsNotifier.storageFull` (`StorageFullState?` with `usage`,
    `fileSizeBytes`, `canFreeSpace`) and `uploadsPaused` (bool). Also
    `Future<void> freeSpaceAndRetry()` and `void dismissStorageFull()`.
  - `String formatGb(int bytes)`: decimal GB, up to 2 decimals, trailing
    zeros trimmed (`400000000` → `0.4 GB`, `980000000` → `0.98 GB`,
    `1000000000` → `1 GB`, `0` → `0 GB`); a non-zero value under 0.01 GB
    → `<0.01 GB`.
  - `String formatMb(int bytes)`: one decimal (`4200000` → `4.2 MB`).
  - `String formatUsageLine(AttachmentUsage u)` →
    `0.4 GB of 1 GB · 120 of 1,000 files` (thousands separators through
    `intl` `NumberFormat.decimalPattern('en')`).

- [ ] **Step 1: Write the failing tests**
  - Format: the exact strings above.
  - Uploader: two 429s and then a success → uploaded; four 429s → failed,
    cause `AttachmentRateLimitedException`; a 413 → failed, cause
    `AttachmentQuotaExceededException`, pending entry kept.
  - Notifier `addFile` + quota refusal → the row is soft-deleted,
    `discard` was called, `storageFull.usage.usedBytes` is set, and `error`
    is null.
  - Notifier `retryUpload` + quota refusal → the row stays `failed`, isn't
    soft-deleted, and `storageFull` is set.
  - `freeSpaceAndRetry` → purger called once, then a single re-add. A
    second refusal sets `storageFull` again; no further retry.
  - `canFreeSpace` is false when `hasPurgeable()` is false.
  - `AttachmentUploadsDisabledException` → `uploadsPaused` true, and the
    row stays `failed`.
  - Dialog widget: renders the exact title and body copy for usage
    980000000/1000000000, 412/1000 files, size 4200000. It hides
    `Free space now` when `canFreeSpace` is false.
- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/ui/format test/ui/widgets/storage_full_dialog_test.dart test/ui/notifiers/dive_attachments_notifier_test.dart test/sync/attachments/attachment_uploader_impl_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement it.** The notifier keeps the last
  `PickedAttachmentFile` for `freeSpaceAndRetry`. Both widgets listen for
  `storageFull` and `uploadsPaused`, show the dialog (or the paused message
  in the existing error banner), and clear the state when it's dismissed.
  A `failed` row whose last failure was a quota refusal shows the label
  `Storage full`. Track that in the notifier by attachment id (session
  only, no schema change).
- [ ] **Step 4: Run the tests and analyze**

Run: `flutter test && flutter analyze`
Expected: all pass, no issues.

- [ ] **Step 5: Commit**

```bash
git add lib/sync/attachments lib/ui test/sync/attachments test/ui
git commit -m "feat(attachments): storage-full dialog and rate-limit retry (#196)"
```

### Task 8: Attachment usage in Settings

**Files:**
- Modify: `lib/ui/screens/settings/sync_tab.dart` (new optional parameter
  and a row under the signed-in account row)
- Modify: `lib/ui/screens/settings_screen.dart` and `lib/ui/app_shell.dart`
  (pass `_attachmentSigner.fetchUsage` through)
- Test: `test/ui/screens/settings/sync_tab_attachment_usage_test.dart`

**Interfaces:**
- Consumes: `AttachmentSigner.fetchUsage` (Task 5), `formatUsageLine` (Task 7).
- Produces: `SyncTab.loadAttachmentUsage: Future<AttachmentUsage> Function()?`.
  When it's null, or when signed out, there's no row.

- [ ] **Step 1: Write the failing widget tests:** signed in with the
  loader returning 400000000 / 1000000000 / 120 / 1000 → a row titled
  `Attachments` showing `0.4 GB of 1 GB · 120 of 1,000 files`, keyed
  `ValueKey('settings-account-attachments')`. A throwing loader → the row
  shows `Unavailable` and nothing throws. A null loader → no row.
- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/ui/screens/settings/sync_tab_attachment_usage_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement it** with a `FutureBuilder` that loads once per
  build of the signed-in branch and shows `…` while loading. Use the
  existing `SettingRow`.
- [ ] **Step 4: Run all tests and analyze**

Run: `flutter test && flutter analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui test/ui
git commit -m "feat(settings): show attachment storage usage (#196)"
```

### Task 9: Wrap-up

- [ ] **Step 1:** Open a follow-up issue: "Deleting a dive leaves its
  attachments live, so their files keep counting against the upload
  limit" (see Out of scope). Link it from #196.
- [ ] **Step 2:** Fix the stale comment in `0004_dive_attachments.sql`
  about a foreground retry sweep. A comment-only change to an applied
  migration is fine; no SQL changes.
- [ ] **Step 3:** Open the PR against `main` (`Closes #196`), ending with
  the attribution line. CI runs `flutter analyze` and `flutter test`; the
  Worker tests are run by hand (`cd worker && npx vitest run`).
