# In-app account deletion — design

_2026-11-08. Status: draft for Egbert's approval._

## 1. Intent

Anchorline 1.1.0 (build 44) is uploaded to the App Store, the Mac App
Store and Google Play. Both stores refuse an app that lets people create
an account but not delete it:

- **Apple, guideline 5.1.1(v).** Deletion must start inside the app. It
  must delete the account record and its personal data, not just
  deactivate it. Email-only or support-flow deletion fails review for an
  app outside a regulated industry. Deletion may take time if the app
  says how long and confirms when it is done. A confirmation step is
  allowed, but making deletion "unnecessarily difficult" fails review.
- **Google Play, User Data policy.** An in-app path to delete the
  account and its data, plus an https web page where people can ask for
  deletion without reinstalling the app. The page must name the app or
  developer, feature the deletion steps prominently, and say what is
  kept and for how long. The link goes in the Data safety form.

Today the Sync tab only offers Sign out, and `docs/PRIVACY.md` tells
people to email. This feature closes that gap so the store listings can
go live.

## 2. Goals, non-goals, anti-goals

**Goals**
- A signed-in user can delete their Anchorline account from Settings →
  Sync, in one flow, with no email or support step.
- Deletion is immediate and complete: the auth user, every cloud row they
  own, every attachment file in R2, and everything Anchorline keeps for
  them on the device they delete from.
- The privacy policy, a public deletion page, and the App Review notes
  say exactly what happens.

**Non-goals**
- Deleting the user's Subsurface Cloud account or the dives in it. That
  is a separate account with another provider.
- Deleting data that is not linked to the account (anonymous Sentry
  crash reports; see §5).
- A grace period or "undo". Apple allows scheduling deletion only if an
  immediate option exists too; immediate-only is simpler.
- GDPR data export. A separate feature; the app currently has no dive
  export at all (see §11).

**Anti-goals** (failures even if it technically works)
- A deletion that leaves the account half-gone with no way to retry.
- A deletion that leaves personal files in R2 with no record of them.
- Anything that could delete another user's data.

## 3. Decisions

**Made by Egbert (2026-11-08):** the server-side step runs as a
**Postgres function**, `public.delete_my_account()`, called by the app
over the Data API. Not a new Dart service, not a manual request queue.

**Defaults proposed by Claude and accepted by Egbert** ("start with
sensible defaults"):

| Question | Answer |
|---|---|
| What is deleted | R2 attachment files, then the Supabase auth user; every owner table cascades from `auth.users` (usage events included). Sentry holds nothing linked to the account. |
| Local data on this device | Wiped, with the same steps as "Reset local data" plus the attachment byte cache. |
| Confirmation | A dialog listing what goes; the user types DELETE. No password re-entry: the app has no password-reset flow, so a user who forgot their password could not delete. |
| Other signed-in devices | Synced data disappears from them through PowerSync while they are online; they are signed out at their next token refresh (within about an hour). |
| Signing up again with the same email | Works immediately and creates a new, empty account. |
| Google Play web link | A public "Delete your Anchorline account" page, sourced from `docs/ACCOUNT_DELETION.md` and published by the website next to the privacy policy, plus an anchored section in the privacy policy itself. |

## 4. Exception to the standing backend decision

The 2026-11-02 decision (sync-service spec §4, branch
`spec/subsurface-sync-service`) puts "account deletion and GDPR export"
in the Dart service. That service does not exist yet, and building its
skeleton would hold up the store launch. Egbert chose a Postgres function
instead. This is a recorded, **temporary** exception:

- When the Dart service is running, account deletion moves into it as a
  route. The app calls deletion through one class
  (`AccountDeletionBackend`), so the switch is a new implementation of
  that class, not a UI change.
- The service then also gets an R2 orphan sweep: list
  `attachments/<uid>/` prefixes and delete those whose `uid` no longer
  exists in `auth.users`. That catches the one case this design cannot
  (§6.3).
- The sync-service spec should get a one-line note pointing here the next
  time it is edited. This design does not edit that branch.

## 5. What is deleted, and what is not

| Data | Where | How it goes |
|---|---|---|
| Account (email, password hash, sessions, refresh tokens, identities) | Supabase Auth | `delete from auth.users`; Supabase cascades its own `auth.*` tables |
| Dives, samples, annotations, cylinders, cells, scrubbers, dive computers, pressure mappings, bailout carry, dive plans, merge links, gas analyses, attachment metadata | Supabase Postgres | `on delete cascade` from `auth.users` (every `owner_id` FK has it, checked 2026-11-08). Bailout carry and merge links also reference dives and cylinders through NO ACTION FKs, so the function deletes those rows first (§6.1) |
| Auth audit log (email and IP address per sign-in event) | Supabase Auth (`auth.audit_log_entries`) | No FK to `auth.users`, so no cascade: the function deletes the caller's entries (`payload->>'actor_id'`) in a guarded block; a post-check confirms (§6.1) |
| Usage events | Supabase Postgres | Same cascade (`usage_events.owner_id … on delete cascade`) |
| Attachment files | Cloudflare R2 | Deleted by the app through the Worker's existing `/delete` route, before the account (§6.3) |
| Replicated copy | PowerSync | Removed as the Postgres deletes replicate |
| Copies on this device | App storage | Wiped (§6.4) |
| Copies on other devices | App storage | Removed by sync while they are online; a device that stays offline keeps its copy until it is reset |
| Crash reports | Sentry | Not deleted: they carry only a random install id, not the account, so they cannot be found. They expire after 30 days. |
| Database backups | Supabase | Not touched; routine backups age out (stated as "up to 7 days" in the policy) |
| Subsurface Cloud account and dives | Subsurface | Not touched; the device keeps the saved Subsurface credentials in the keychain (they belong to that other account) |

The app does not use Supabase Storage, which would otherwise block
deleting the auth user.

## 6. How it works

### 6.1 The migration

`supabase/migrations/0022_delete_my_account.sql`:

```sql
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
set statement_timeout = '50s'
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not signed in' using errcode = '28000';
  end if;

  -- NO ACTION FKs: delete the referencing rows (any owner) first.
  delete from public.dive_bailout_carry
  where dive_id in (select id from public.dives where owner_id = uid)
     or cylinder_id in (select id from public.cylinders where owner_id = uid);
  delete from public.dive_merge_links
  where id in (select id from public.dives where owner_id = uid);

  -- Email and IP; guarded so a missing privilege cannot block the delete.
  begin
    delete from auth.audit_log_entries where payload->>'actor_id' = uid::text;
  exception when insufficient_privilege or undefined_table then
    null;
  end;

  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
```

- **Security definer** is needed because `authenticated` has no rights on
  `auth.users`. The body deletes only the caller's own row
  (`auth.uid()`), refuses an unauthenticated call, pins `search_path`,
  and is not executable by `anon` or `PUBLIC`.
- **One transaction.** The cascade either removes everything or nothing.
- **NO ACTION children first.** `dive_bailout_carry.dive_id`,
  `dive_bailout_carry.cylinder_id` and `dive_merge_links.id` reference
  dives and cylinders without `on delete cascade`. Deleting those rows
  explicitly means the auth delete never depends on the order the
  cascades run in. It also removes rows of another owner that point at
  this user's dives or cylinders; they could not survive the delete
  anyway.
- **Audit log.** `auth.audit_log_entries` holds the email and IP address
  of each auth event and has no FK to `auth.users`. The function deletes
  the caller's entries inside a nested block that ignores
  `insufficient_privilege` and `undefined_table`, so a missing privilege
  leaves the entries behind (caught by the post-check below) instead of
  blocking the deletion.
- **Timeout.** `authenticated` defaults to 8 s. PostgREST applies a
  function-level `statement_timeout` to RPC calls, and Supabase caps
  client queries at 60 s, so 50 s leaves headroom for a large log.
- **Idempotent** (`create or replace`) and lint-clean. It creates no
  table, so the grant lint has nothing to check, but the explicit
  `revoke`/`grant` follows the same rule.
- Nothing is created in the `auth` schema (Supabase has forbidden that
  since 2025-04-21; deleting rows from `auth.users` through a function in
  `public` is not covered by that restriction).

**Before deploying**, Egbert runs these in the SQL Editor (also in
`supabase/README.md`):
1. `select has_table_privilege('postgres', 'auth.users', 'DELETE');` →
   `true`.
2. Apply the migration, create a throwaway account in the app, add a dive
   and an attachment, add a bailout-carry entry to a dive, merge two
   dives, delete the account from the app, then check the user is gone
   from Authentication → Users and its rows from `dives`.
3. Post-check: `select count(*) from auth.audit_log_entries where
   payload->>'actor_id' = '<uid>';` → 0. Otherwise the guarded delete
   lacked the privilege; the entries hold the email and IP, and Egbert
   decides whether to delete them by hand or disclose them.

Optionally, a rollback dry run against a real user id raises any FK error
the deletion would hit without deleting anything:

```sql
begin;
select set_config('request.jwt.claims', '{"sub":"<uid>","role":"authenticated"}', true);
select public.delete_my_account();
rollback;
```

If step 1 is `false`, stop: the fallback is a request queue or the Dart
service, and the decision goes back to Egbert.

### 6.2 The app flow

New class `AccountDeleter` (`lib/sync/cloud/account_deleter.dart`). The
UI calls `deleteAccount()`, which reports progress and returns a result.
Steps, in order:

1. **Check online and refresh the session.** `SessionSource.refreshSession()`
   (the existing seam in `ccrlogger_backend_connector.dart`). A
   non-retryable `AuthException` (anything but
   `AuthRetryableFetchException`; gotrue has then removed the session
   itself), or no user id on the session afterwards → `sessionEnded`.
   Any other failure → `offline`. Either way nothing has changed. A fresh
   token also covers the R2 sweep, so the JWT cannot expire mid-flow.
2. **Pause sync.** `CloudSyncCoordinator.pause()` disconnects PowerSync
   and stops it reconnecting (auth notifications and resume-from-sleep
   both reconnect today). This stops queued uploads from racing the
   delete and makes a failed attempt leave things as they were.
3. **Collect attachment keys.** The union of the server's list
   (`select storage_key from dive_attachments where storage_key is not
   null`, RLS-scoped, paged past PostgREST's 1000-row limit, includes
   soft-deleted rows) and the local list
   (`DiveAttachmentsDao.listAllStorageKeys()`, covering files uploaded
   from this device whose rows have not synced yet). Paging advances by
   the rows returned and stops only on an empty page. Only keys starting
   with `attachments/<uid>/` (the session's user id after step 1) are
   kept; any other key is skipped silently, since the Worker refuses it
   and it would fail every retry.
4. **Delete attachment files** through `AttachmentSigner.deleteObject`,
   each attempt limited to 30 s, retrying each failure (a timeout
   included) once. If any still fail → `attachments` failure: resume
   sync, account untouched. (R2 deletes are idempotent, so a retry of the
   whole flow is safe.)
5. **Delete the account.** `rpc('delete_my_account')`, limited to 60 s
   (above the function's 50 s `statement_timeout`). On a failure or
   timeout the response may have been lost after the commit, so the app
   asks `AccountDeletionBackend.accountExists()` (`auth.getUser()`;
   GoTrue answers a valid JWT whose user is gone with 403
   `user_not_found`; 30 s limit). Gone → carry on with step 6 and report
   success. Still there, or the probe fails → `account` failure: resume
   sync. The attachment files are already gone; the message says so.
6. **Sign out** locally (`AuthService.signOut()`; gotrue already ignores
   the 403/404 a deleted user gets from `/logout`).
7. **Wipe this device**: `LocalDataWiper.wipe()` (§6.4), then, in a
   `finally` so they run even if the wipe throws, the pending-upload
   paths (best effort) and `AttachmentCache.clear()`. Failure here →
   `localWipe` result: the account *is* deleted; the message points to
   Reset local data.
8. **Resume** the coordinator (always, in a `finally`), so a later
   sign-in connects normally.

Result type (sealed): `AccountDeleted`, or `AccountDeletionFailed` with a
stage (`offline`, `sessionEnded`, `attachments`, `account`, `localWipe`)
and the underlying message (`.message` for `PostgrestException` and
`AuthException`, `toString()` otherwise). No usage event is logged for
deletion; it would be deleted with the account anyway.

### 6.3 Why attachments go first, and the gap

R2 objects are found only through `dive_attachments` rows. Deleting the
account first would cascade those rows away and lose the list, leaving
files nobody can find. Deleting files first means the worst partial state
is "some attachments gone, account still there", which the user is about
to fix by retrying.

The gap: a file uploaded to R2 whose row never reached Postgres *and* is
not on this device (for example uploaded from another device that then
lost its local database). It cannot be listed by the app. The Dart
service's orphan sweep (§4) closes it later; until then such files are
rare and inert (only reachable with a presigned URL for that user's key).

The same holds for an upload already in flight when the flow starts: it
sets `storage_key` only after its PUT, so its object can be missed. That
is rare under the modal UI, and the orphan sweep closes it later.

### 6.4 `LocalDataWiper`

The body of today's `_confirmAndResetLocalData` (Drift deletes,
`disconnectAndClear()`, the belt-and-braces `ps_data__*` deletes,
`markFixturesBlocked()`) moves out of `settings_screen.dart` into
`lib/data/local_data_wiper.dart` so Reset local data and account deletion
share it. Reset local data keeps its exact behaviour and dialog.
The extraction may also extend the belt-and-braces table list to the
PowerSync tables added since it was written (bailout carry, gas analyses,
dive plans, merge links), ideally derived from the PowerSync schema.

### 6.5 Other devices

Nothing new runs on them. While online they receive the cascaded deletes
through PowerSync, so the synced data disappears. Their access token
stays valid until it expires (Supabase cannot revoke issued JWTs), but
the refresh then fails, gotrue removes the session and emits
`signedOut`, and the coordinator disconnects. Any upload they attempt in
that window fails on the `owner_id → auth.users` foreign key, so nothing
is recreated for the deleted account. A device offline the whole time
keeps its local copy until the user resets it or signs in to another
account.

### 6.6 Signing up again

Supabase frees the email at deletion. Signing up again creates a new user
id with no data. Nothing links the old and new accounts.

## 7. The UI

**Where.** Settings → Sync → "Anchorline account" group, a new danger row
**Delete account** under the signed-in row, shown only when signed in.
Helper text: "Deletes your account and all its data".

**Confirm dialog.** Title "Delete your Anchorline account?". Body:

> This permanently deletes:
> • your account and sign-in
> • every dive, note, equipment item and gas analysis in the cloud
> • all attachment files
> • the dives and data on this device
>
> Other devices signed in to this account are signed out within about an
> hour. Dives in Subsurface Cloud and on your dive computer are not
> affected.
>
> This can't be undone. Type DELETE to confirm.

A text field (case-insensitive, trimmed match), Cancel, and a
danger-styled **Delete account** button enabled only when the text
matches. The field gets the post-frame focus workaround the auth dialog
uses for macOS.

**Progress.** A non-dismissible dialog: "Deleting your account…" with
the current step ("Removing attachment files (3 of 12)", "Deleting your
account", "Clearing this device").

**Result.**
- Success: "Account deleted. Your Anchorline account and its data have
  been deleted. Quit and reopen Anchorline to finish clearing this
  device." (The quit-and-reopen line matches Reset local data, which
  needs it today.) This dialog is Apple's "confirmation when the
  deletion is complete".
- `offline`: "You need an internet connection to delete your account.
  Nothing was deleted."
- `sessionEnded`: "Your sign-in has ended, so nothing was deleted. Sign
  in again, then try again."
- `attachments`: "Your account was not deleted. N attachment files could
  not be removed. Check your connection and try again."
- `account`: "Your account was not deleted. Attachment files were
  already removed. Try again later." plus the error text. No email
  address in the app: the support mailbox is changing, and text in a
  shipped binary can't be corrected.
- `localWipe`: "Your account was deleted, but clearing this device
  failed. Use Reset local data in Settings → Sync."

Wording may be tightened by the builder; the facts in each message may
not change.

## 8. Documents

- **`docs/PRIVACY.md`** is owned by the website session, which is
  rewriting it (CCRLog → Anchorline) and carries the deletion text in the
  same PR (agreed 2026-11-08, to keep one PR per file). This PR does not
  edit it. The content it carries: a section "Deleting your account"
  (anchor `#deleting-your-account`) with the in-app steps, the email path
  for people without the app, what goes and what stays (§5), the timing
  (immediately in the app; by email within 5 working days, at most 30
  days) and re-sign-up; the retention list, usage-statistics opt-out,
  TL;DR line and "Erase" right updated to point at in-app deletion.
  Wording changes go to the website session, not into this branch.
- **`docs/ACCOUNT_DELETION.md`** (new): the public page for Google Play,
  published by the website at `https://anchorline.eu/delete-account`.
  Names Anchorline and its developer (Egbert De Pauw, personally), gives
  the in-app steps first, then "No longer have the app? Email … from the
  address you signed up with" (`support@anchorline.eu`; confirmed within
  5 working days, completed within 30 days, as in the privacy policy;
  the site goes live only once that mailbox receives), what is deleted
  and kept, and a link to the privacy
  policy section. Short and self-contained.
- **`docs/APP_STORE_SUBMISSION.md`**: §5 review notes gain "Account
  deletion: Settings → Sync → Delete account, type DELETE; immediate."
  and "Create a fresh review account before each submission; the
  reviewer may delete it." §10's deletion bullet points at the in-app
  flow and the deletion page.
- **`docs/BETA_DISTRIBUTION.md`**: the Play "Data safety" item gains the
  data-deletion answers (in-app path, the page URL, "data is deleted, not
  just the account").
- **`supabase/README.md`**: the pre-deploy check from §6.1, and a short
  runbook for an email request (verify the sender is the account's
  address; note the user id; delete `attachments/<uid>/` in the R2
  dashboard; run the function's NO ACTION child deletes and audit-log
  delete for that uid in the SQL Editor, since the dashboard delete does
  not run the function; delete the user under Authentication → Users;
  reply to confirm).
- **Website** (agreed with the website session 2026-11-08): it publishes
  `docs/ACCOUNT_DELETION.md` at `https://anchorline.eu/delete-account`
  next to the privacy policy (`https://anchorline.eu/privacy`). Until the
  site exists, the Play Console URL is the privacy policy's current host
  plus `#deleting-your-account`.

## 9. Testing

- **`AccountDeleter` unit tests** with fakes for every dependency: the
  happy path calls the steps in order; offline stops before pausing sync;
  an R2 failure retries once, then stops before the RPC and resumes sync;
  an RPC failure resumes sync and does not wipe; a wipe failure reports
  `localWipe` after sign-out; keys from server and local lists are
  deduplicated; server paging fetches past 1000 rows; resume always runs.
- **`CloudSyncCoordinator`**: `pause()` disconnects and suppresses
  reconnect from auth notifications and `forceReconnect()`; `resume()`
  reconciles.
- **Widget tests** for the Sync tab: the row shows only when signed in;
  the Delete button stays disabled until DELETE is typed; Cancel does
  nothing; confirming calls the deleter; each result shows its dialog.
- **Reset local data** keeps its existing tests green after the
  extraction.
- `./supabase/lint_migrations.sh`, `flutter analyze` clean, `flutter
  test` passing.
- **Manual, by Egbert after deploying the migration:** §6.1 step 2 on a
  real device.

## 10. Rollout

1. PR with the migration, app code, tests and docs.
2. Egbert runs the §6.1 checks and applies migration 0022 with
   `supabase/apply_migrations.sh`.
3. Build 45 with the feature; replace build 44 in the store submissions.
4. The website session's PR lands the privacy policy with the deletion
   section; the website publishes `https://anchorline.eu/delete-account`.
   Egbert enters that URL (or, until the site exists, the current privacy
   policy URL plus `#deleting-your-account`) in Play Console → Data
   safety → Data deletion.
5. Fresh review account for each store submission.

The migration is safe to deploy before the app ships (nothing calls it),
and build 44 users are unaffected.

## 11. Left to the builder, and follow-ups

**Builder's calls:** class and file names beyond those above; R2 delete
concurrency; exact progress wording; whether `LocalDataWiper` derives its
table list from the PowerSync schema.

**Follow-ups outside this design** (noted, not done here):
- `docs/PRIVACY.md`'s rename to Anchorline, PowerSync in "Where data is
  stored", and removing the stale XML/UDDF export claim are all in the
  website session's rewrite.
- R2 orphan sweep and moving deletion into the Dart service (§4).
- The sync-service spec's §4 note (§4 above).
