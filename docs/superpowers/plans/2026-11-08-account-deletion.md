# In-app Account Deletion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A signed-in user can delete their Anchorline account from Settings → Sync; the auth user, every cloud row, every R2 attachment file and this device's data go, immediately.

**Architecture:** A `security definer` Postgres function `public.delete_my_account()` deletes the caller's `auth.users` row; every owner table cascades. The app's `AccountDeleter` pauses sync, deletes R2 files through the existing Worker route, calls the function, signs out and wipes the device with a `LocalDataWiper` extracted from today's Reset local data.

**Tech Stack:** Flutter/Dart, supabase_flutter (PostgREST RPC), PowerSync, Drift, Postgres (Supabase).

**Spec:** `docs/superpowers/specs/2026-11-08-account-deletion-design.md`

## Global Constraints

- Everything in git is English; Conventional Commits (`feat:`, `docs:`, `refactor:`, `test:`).
- Never run `dart format` on whole files; match the surrounding style by hand.
- `flutter analyze` clean and `flutter test` passing before the PR; `./supabase/lint_migrations.sh` passing.
- Migration number is `0022`; it is deployed by Egbert, not by the builder.
- Function: `public.delete_my_account()`, `security definer`, `set search_path = ''`, `set statement_timeout = '50s'`, raises errcode `28000` when `auth.uid()` is null, `revoke all … from public, anon`, `grant execute … to authenticated`.
- Confirmation word: `DELETE`, matched case-insensitively after trimming.
- No usage event is logged for deletion. No password re-entry.
- Dives live in PowerSync, not Drift: read attachment keys through `DiveAttachmentsDao` (PowerSync), never `_drift.select`.
- Deletion order is fixed: refresh session → pause sync → collect keys → delete R2 files → RPC → sign out → wipe device → resume sync (always).
- No email address in app text. `docs/PRIVACY.md` is owned by the website session's PR: do not edit it in this branch.
- `docs/ACCOUNT_DELETION.md` uses `support@anchorline.eu` and the privacy policy's email timing (confirmed within 5 working days, completed within 30 days); developer is "Egbert De Pauw"; published URL `https://anchorline.eu/delete-account`. The site goes live only once that mailbox receives (website spec gate).

## Review Focus

1. **Double start.** Tapping Delete again, or a second call while a deletion runs, must not start a second run: `AccountDeleter.deleteAccount` returns the in-flight future. (Test in Task 4.)
2. **Resume from sleep mid-deletion.** `AppShell` calls `forceReconnect()` on lifecycle resume; while paused it must not reconnect PowerSync. (Test in Task 3.)
3. **Session gone mid-sweep.** `AttachmentSigner.deleteObject` throws `SignerNoSessionException` or `SignerAuthException`; that counts as a failed attachment (stage `attachments`), never an uncaught crash. (Test in Task 4.)
4. **Sign-out throws after the account is gone.** A network error from `signOut()` after a successful RPC must not stop the device wipe; the result is still `AccountDeleted`. (Test in Task 4.)
5. **Many attachments.** More than 1000 server rows are all fetched (PostgREST caps a page at 1000). (Test in Task 4.)

---

### Task 1: Migration `0022_delete_my_account.sql` and the operator notes

**Files:**
- Create: `supabase/migrations/0022_delete_my_account.sql`
- Modify: `supabase/README.md` (append two sections)

**Interfaces:**
- Produces: RPC `delete_my_account` (no arguments, returns void) used by Task 4.

- [ ] **Step 1: Write the migration** exactly as spec §6.1, preceded by a header comment in the style of `0018_keepalive_function.sql`: what it does, why `security definer` is needed and safe (only `auth.uid()`'s row; anon/public revoked), that every `owner_id` FK cascades, that nothing is created in the `auth` schema, and that it is a temporary exception to the Dart-service decision (spec §4).
- [ ] **Step 2: Run the lint.** Run: `./supabase/lint_migrations.sh` — Expected: `OK: all migrations are idempotent and every table has explicit Data API grants.`
- [ ] **Step 3: Append to `supabase/README.md`** a section "Before deploying 0022" with spec §6.1's two checks verbatim in substance (the `has_table_privilege` query must return `true`; the throwaway-account end-to-end check; stop and go back to Egbert if the first is `false`), and a section "Deleting an account on request (email)" with spec §8's runbook: verify the sender is the account's address, note the user id, delete `attachments/<uid>/` in the R2 dashboard, delete the user under Authentication → Users (rows cascade), reply to confirm, within 30 days.
- [ ] **Step 4: Commit.** `git commit -m "feat(supabase): delete_my_account() for in-app account deletion"`

### Task 2: Extract `LocalDataWiper`

**Files:**
- Create: `lib/data/local_data_wiper.dart`
- Modify: `lib/ui/screens/settings_screen.dart` (`_confirmAndResetLocalData`, ~lines 722–790)
- Test: `test/data/local_data_wiper_test.dart`

**Interfaces:**
- Produces: `class LocalDataWiper { LocalDataWiper({required AppDatabase db, required PowerSyncDatabase powerSyncDb, Future<void> Function()? markFixturesBlocked}); Future<void> wipe(); }` — `markFixturesBlocked` defaults to the function in `lib/dev/fixture_seeder.dart`.

- [ ] **Step 1: Write the failing test** `wipe() empties Drift and PowerSync tables and blocks fixtures`: open `AppDatabase(NativeDatabase.memory())` and `openPowerSyncForTest()` (`test/_helpers/powersync_test_helper.dart`); insert one row into Drift `dives` and one into PowerSync `dives` and `gas_analyses` (any valid columns from `appSchema`); pass a recording `markFixturesBlocked`; call `wipe()`; assert both `dives` tables and `gas_analyses` are empty and the recorder was called once.
- [ ] **Step 2: Run it.** `flutter test test/data/local_data_wiper_test.dart` — Expected: FAIL (file/class missing).
- [ ] **Step 3: Implement `LocalDataWiper.wipe()`** by moving the body of the `try` block's local part (the Drift transaction, `disconnectAndClear()`, the belt-and-braces deletes, `markFixturesBlocked()`) verbatim from `_confirmAndResetLocalData`, keeping its comments. Change one thing: build the belt-and-braces list from `appSchema.tables` (`'ps_data__${t.name}'`) plus `ps_crud`, `ps_oplog`, `ps_buckets`, so newer tables (bailout carry, gas analyses, dive plans, merge links) are covered. Keep the per-table `try/catch`-around-the-loop behaviour.
- [ ] **Step 4: Make `_confirmAndResetLocalData` call** `LocalDataWiper(db: db, powerSyncDb: psDb).wipe()` in place of the moved code. The dialog, the R2/cloud wipe ordering and the snackbars do not change.
- [ ] **Step 5: Run.** `flutter test test/data/local_data_wiper_test.dart test/ui/screens/settings_screen_test.dart` — Expected: PASS.
- [ ] **Step 6: Commit.** `git commit -m "refactor(settings): extract LocalDataWiper from Reset local data"`

### Task 3: Pausable `CloudSyncCoordinator`

**Files:**
- Modify: `lib/sync/cloud/cloud_sync_coordinator.dart`
- Test: `test/sync/cloud/cloud_sync_coordinator_test.dart` (add a `group('pause', …)`)

**Interfaces:**
- Produces: `abstract class SyncPause { Future<void> pause(); Future<void> resume(); }` declared in `cloud_sync_coordinator.dart`; `CloudSyncCoordinator implements SyncPause`.

- [ ] **Step 1: Write the failing tests** using the file's `_RecordingTarget` and `_FakeAuthClient`:
  - `pause disconnects a connected coordinator` — signed in, `start()`, `pause()` → `disconnectCalls == 1`, `isConnected == false`.
  - `auth changes do not reconnect while paused` — after `pause()`, trigger an `AuthService` notification (e.g. a successful `signIn` through the fake) → `connectCalls` unchanged.
  - `forceReconnect is a no-op while paused` — `connectCalls` unchanged.
  - `resume reconnects when signed in` and `resume stays disconnected when signed out`.
- [ ] **Step 2: Run.** `flutter test test/sync/cloud/cloud_sync_coordinator_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement** a `_paused` flag: `pause()` sets it and awaits `_disconnect()`; `_reconcile()` and `forceReconnect()` return early while paused; `resume()` clears it and calls `_reconcile()`. Update the library doc comment with one sentence on why pausing exists (account deletion).
- [ ] **Step 4: Run** the same command — Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "feat(sync): let account deletion pause the sync coordinator"`

### Task 4: `AccountDeleter`

**Files:**
- Create: `lib/sync/cloud/account_deleter.dart`
- Test: `test/sync/cloud/account_deleter_test.dart`

**Interfaces:**
- Consumes: `SyncPause` (Task 3); `SessionSource` from `ccrlogger_backend_connector.dart`; RPC `delete_my_account` (Task 1).
- Produces:
  ```dart
  abstract class AccountDeletionBackend {
    Future<List<String>> listStorageKeys(); // server-side, all pages
    Future<void> deleteAccount();           // rpc('delete_my_account')
  }
  class SupabaseAccountDeletionBackend implements AccountDeletionBackend {
    SupabaseAccountDeletionBackend(SupabaseClient client, {int pageSize = 1000});
  }
  enum AccountDeletionStep { checking, removingAttachments, deletingAccount, clearingDevice }
  class AccountDeletionProgress { final AccountDeletionStep step; final int done; final int total; }
  enum AccountDeletionStage { offline, attachments, account, localWipe }
  sealed class AccountDeletionResult {}
  final class AccountDeleted extends AccountDeletionResult {}
  final class AccountDeletionFailed extends AccountDeletionResult {
    final AccountDeletionStage stage; final String message; final int failedAttachments;
  }
  class AccountDeleter {
    AccountDeleter({
      required SessionSource session,
      required AccountDeletionBackend backend,
      required SyncPause sync,
      required Future<List<String>> Function() localStorageKeys,
      required Future<void> Function(String objectKey) deleteObject,
      required Future<void> Function() signOut,
      required Future<void> Function() wipeLocal,
    });
    Future<AccountDeletionResult> deleteAccount({void Function(AccountDeletionProgress)? onProgress});
  }
  ```

- [ ] **Step 1: Write the failing tests** with hand-written fakes that append to one shared `List<String> calls` log:
  - `happy path runs the steps in order` — calls equal `['refresh', 'pause', 'serverKeys', 'localKeys', 'delete:a', 'delete:b', 'rpc', 'signOut', 'wipe', 'resume']` (server `['a']`, local `['a', 'b']`; dedupe keeps first-seen order: server keys, then local-only keys); result `AccountDeleted`.
  - `offline: refresh failure stops before pausing` — refresh throws → `AccountDeletionFailed(stage: offline)`; calls `== ['refresh']`.
  - `an attachment failure is retried once` — `deleteObject('a')` throws once then succeeds → `AccountDeleted`; `delete:a` appears twice.
  - `a persistent attachment failure stops before the rpc` — `deleteObject('b')` always throws `SignerAuthException('x')` → stage `attachments`, `failedAttachments == 1`; no `rpc`, no `wipe`; last call `resume`.
  - `an rpc failure resumes sync and does not wipe` — stage `account`; no `signOut`, no `wipe`; last call `resume`.
  - `a sign-out error does not stop the wipe` — `signOut` throws → `AccountDeleted`; `wipe` called.
  - `a wipe failure reports localWipe after signing out` — stage `localWipe`; `signOut` before `wipe`; last call `resume`.
  - `a second call while running returns the same future` — gate the RPC on a `Completer`; call `deleteAccount()` twice; `identical(f1, f2)`; `rpc` appears once.
  - `progress reports each step` — collected steps contain `checking`, `removingAttachments` with `done` counting `1..total`, `deletingAccount`, `clearingDevice`, in that order.
  - `SupabaseAccountDeletionBackend pages past 1000 rows` — only if a page fetch can be faked without the full query builder; otherwise extract the paging loop as `@visibleForTesting static Future<List<String>> fetchAllPages(Future<List<String>> Function(int from, int to) page, {int pageSize})` and test it: pages of 1000, 1000, 3 → 2003 keys; stops on a short page.
- [ ] **Step 2: Run.** `flutter test test/sync/cloud/account_deleter_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement** per spec §6.2. Attachment deletes may run with small concurrency (≤4); each key gets one retry; collect failures, then fail if any remain. `SupabaseAccountDeletionBackend.listStorageKeys` selects `storage_key` from `dive_attachments` where `storage_key` is not null, ordered by `id`, with `.range(from, to)` pages. `deleteAccount` is `client.rpc('delete_my_account')`. The in-flight guard keeps the running `Future` in a field and clears it in `whenComplete`. `resume()` runs in a `finally` once `pause()` has run. Library doc comment: the order and why attachments go first (spec §6.3).
- [ ] **Step 4: Run** the same command — Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "feat(account): AccountDeleter for in-app account deletion"`

### Task 5: The Delete account UI and wiring

**Files:**
- Create: `lib/ui/screens/settings/delete_account_flow.dart`
- Modify: `lib/ui/screens/settings/sync_tab.dart`, `lib/ui/screens/settings_screen.dart`, `lib/ui/app_shell.dart`
- Test: `test/ui/screens/settings/delete_account_flow_test.dart`; extend `test/ui/screens/settings_screen_test.dart`

**Interfaces:**
- Consumes: `AccountDeleter`, results and progress types (Task 4); `LocalDataWiper` (Task 2); `CloudSyncCoordinator` as `SyncPause` (Task 3).
- Produces: `Future<void> runDeleteAccountFlow(BuildContext context, AccountDeleter deleter)`; `SyncTab({…, VoidCallback? onDeleteAccount})`; `SettingsScreen({…, AccountDeleter? accountDeleter})`.

- [ ] **Step 1: Write the failing widget tests.** In `delete_account_flow_test.dart`, pump a button that calls `runDeleteAccountFlow` with an `AccountDeleter` built from fakes (reuse the Task 4 fake shapes locally):
  - `the Delete button is disabled until DELETE is typed` — enter `'delet'` → disabled; enter `' delete '` → enabled.
  - `Cancel deletes nothing` — fake RPC never called.
  - `success shows the Account deleted dialog` — text `'Account deleted'` and the quit-and-reopen sentence.
  - one test per failure stage asserting its message's key phrase: offline `'Nothing was deleted.'`, attachments `'Your account was not deleted.'` with the count, account `'Attachment files were already removed.'`, localWipe `'Reset local data'`.
  In `settings_screen_test.dart`: `Delete account row shows only when signed in` (key `settings-account-delete`, danger-styled title like the reset row test) and absent when signed out or when `accountDeleter` is null.
- [ ] **Step 2: Run.** `flutter test test/ui/screens/settings/delete_account_flow_test.dart test/ui/screens/settings_screen_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement `runDeleteAccountFlow`**: the confirm dialog with spec §7's title and body copy verbatim, a `TextField` with the post-frame `requestFocus` workaround from `_AuthSheetState.initState`, Cancel and a danger-styled `FilledButton.tonal` "Delete account" (same styling as the reset dialog) enabled only on a match; then a non-dismissible progress dialog (`PopScope(canPop: false)`) whose text follows `onProgress` (spec §7 step wording); then a result `AlertDialog` per spec §7.
- [ ] **Step 4: Add the row.** In `SyncTab`, when signed in and `onDeleteAccount != null`, render a `SettingRow(key: ValueKey('settings-account-delete'), title: 'Delete account', helper: 'Deletes your account and all its data', danger: true, onTap: onDeleteAccount)` under `_SignedInRow` inside the same `ListenableBuilder`. In `SettingsScreen`, add `accountDeleter` and pass `onDeleteAccount: deleter == null ? null : () => runDeleteAccountFlow(context, deleter)`.
- [ ] **Step 5: Wire it in `AppShell.initState`** after `_attachmentObjectWiper`: build `AccountDeleter` with `SupabaseAuthSessionSource(Supabase.instance.client)`, `SupabaseAccountDeletionBackend(Supabase.instance.client)`, `widget.cloudSyncCoordinator`, `_diveAttachmentsDao.listAllStorageKeys`, `(k) => _attachmentSigner.deleteObject(objectKey: k)`, `widget.authService.signOut`, and a `wipeLocal` that awaits `LocalDataWiper(db: widget.db, powerSyncDb: widget.powerSyncDb).wipe()` then `_attachmentCache.clear()`. Pass it to `SettingsScreen(accountDeleter: …)`.
- [ ] **Step 6: Run** the Step 2 command, then `flutter analyze` — Expected: PASS, `No issues found!`
- [ ] **Step 7: Commit.** `git commit -m "feat(settings): Delete account in Settings → Sync"`

### Task 6: Deletion page and store notes

**Files:**
- Create: `docs/ACCOUNT_DELETION.md`
- Modify: `docs/APP_STORE_SUBMISSION.md`, `docs/BETA_DISTRIBUTION.md`
- Not this branch: `docs/PRIVACY.md` (the website session's PR carries the deletion section, spec §8)

- [ ] **Step 1: `docs/ACCOUNT_DELETION.md`**: title "Delete your Anchorline account"; first line names the app and developer (Egbert De Pauw); in-app steps first ("Settings → Sync → Delete account, type DELETE; deletion is immediate"); "No longer have the app?" email path with the subject line "Delete my Anchorline account", sent to `support@anchorline.eu` from the account's address, confirmed within 5 working days and completed within 30 days, with a reply when done; what is deleted and what is kept, in plain words from spec §5 (Sentry's unlinked 30-day crash reports, backups "up to 7 days", Subsurface Cloud untouched); signing up again gives a new, empty account; link to `https://anchorline.eu/privacy#deleting-your-account`.
- [ ] **Step 2: `docs/APP_STORE_SUBMISSION.md`**: §5 notes gain the deletion path and "deletion is immediate", plus "create a fresh review account before each submission; the reviewer may delete it"; §10's deletion bullet points at the in-app flow and `https://anchorline.eu/delete-account`.
- [ ] **Step 3: `docs/BETA_DISTRIBUTION.md`**: the Data safety bullet gains the Data deletion answers (users can request deletion: yes; in-app path; the URL `https://anchorline.eu/delete-account`, or the current privacy policy URL plus `#deleting-your-account` until the site exists; data is deleted with the account).
- [ ] **Step 4: Check the website session's `docs/PRIVACY.md`** deletion section against spec §5 and §8; send any wording change to that session instead of editing the file.
- [ ] **Step 5: Commit.** `git commit -m "docs: account deletion page and store review notes"`

### Task 7: Verify, issue, PR

- [ ] **Step 1:** `flutter analyze` → `No issues found!`; `flutter test` → all pass; `./supabase/lint_migrations.sh` → OK.
- [ ] **Step 2:** `gh issue create` (title "In-app account deletion for App Store and Google Play review", body: the store rules, the decision, link to the spec) and label it `P0` if that label exists.
- [ ] **Step 3:** Push the branch and open the PR referencing the issue ("Closes #N"), with the deploy steps from spec §10 as a checklist for Egbert (pre-deploy checks, apply 0022, build 45, Play Console URL, fresh review account).
