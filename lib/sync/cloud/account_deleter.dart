/// Runs the in-app "Delete account" flow (spec 2026-11-08, section 6.2).
///
/// The order is load-bearing:
///
/// 1. Refresh the session (doubles as the online check). A rejected
///    refresh means the sign-in has ended, not that the device is offline.
/// 2. Pause sync, so queued uploads cannot race the delete.
/// 3. Collect attachment keys (server list plus this device's list), kept
///    only when they are under this user's `attachments/<uid>/` prefix.
/// 4. Delete the attachment files from R2.
/// 5. Delete the account (Postgres function; every cloud row cascades).
///    If the call fails or times out, ask the server whether the account
///    still exists: the response may have been lost after the commit.
/// 6. Sign out, then wipe this device.
/// 7. Resume sync (always), so a later sign-in connects normally.
///
/// Why attachments go first (spec 6.3): R2 objects are found only through
/// `dive_attachments` rows. Deleting the account first would cascade those
/// rows away and lose the list, leaving files nobody can find. Deleting
/// files first means the worst partial state is "some attachments gone,
/// account still there", which a retry fixes (R2 deletes are idempotent).
///
/// No usage event is logged; it would be deleted with the account anyway.
library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ccrlogger_backend_connector.dart';
import 'cloud_sync_coordinator.dart';

/// Server-side operations, behind a seam so tests need no Supabase client.
abstract class AccountDeletionBackend {
  /// Every non-null `storage_key` of the caller's attachments, all pages.
  Future<List<String>> listStorageKeys();

  /// Calls the `delete_my_account` Postgres function.
  Future<void> deleteAccount();

  /// Whether the signed-in user still exists on the server. Asked after a
  /// failed [deleteAccount], because the delete may have committed and only
  /// the response was lost. Returns `false` only when the server says the
  /// user is gone; throws when it cannot tell.
  Future<bool> accountExists();
}

class SupabaseAccountDeletionBackend implements AccountDeletionBackend {
  SupabaseAccountDeletionBackend(this._client, {this.pageSize = 1000});

  final SupabaseClient _client;
  final int pageSize;

  @override
  Future<List<String>> listStorageKeys() => fetchAllPages(
        (from, to) async {
          final rows = await _client
              .from('dive_attachments')
              .select('storage_key')
              .not('storage_key', 'is', null)
              .order('id')
              .range(from, to);
          return [
            for (final row in rows)
              if (row['storage_key'] is String) row['storage_key'] as String,
          ];
        },
        pageSize: pageSize,
      );

  @override
  Future<void> deleteAccount() => _client.rpc('delete_my_account');

  /// `GET /user` with the current access token. The token outlives the
  /// user (issued JWTs cannot be revoked), and GoTrue answers it with a 403
  /// carrying the code `user_not_found` once the auth.users row is gone.
  @override
  Future<bool> accountExists() async {
    try {
      await _client.auth.getUser();
      return true;
    } on AuthException catch (e) {
      if (isUserGone(e)) return false;
      rethrow;
    }
  }

  /// Whether [e] is GoTrue saying the JWT's user no longer exists. Matched
  /// on the error code only: gotrue 2.20.0 puts it in [AuthException.code]
  /// (from `code` or the older `error_code` body field) whatever the HTTP
  /// status, and its `ErrorCode` enum is not exported, hence the literal.
  @visibleForTesting
  static bool isUserGone(AuthException e) => e.code == 'user_not_found';

  /// Pages through [page] (inclusive `from`/`to` row indexes) until a page
  /// comes back empty. PostgREST caps a response at 1000 rows by default,
  /// hence the loop. `from` moves by the rows actually returned, and only an
  /// empty page stops it, so a server cap below [pageSize] (a short page
  /// that is not the last) cannot skip keys.
  @visibleForTesting
  static Future<List<String>> fetchAllPages(
    Future<List<String>> Function(int from, int to) page, {
    int pageSize = 1000,
  }) async {
    final all = <String>[];
    var from = 0;
    while (true) {
      final chunk = await page(from, from + pageSize - 1);
      if (chunk.isEmpty) break;
      all.addAll(chunk);
      from += chunk.length;
    }
    return all;
  }
}

enum AccountDeletionStep {
  checking,
  removingAttachments,
  deletingAccount,
  clearingDevice,
}

class AccountDeletionProgress {
  const AccountDeletionProgress(this.step, {this.done = 0, this.total = 0});

  final AccountDeletionStep step;

  /// Only meaningful for [AccountDeletionStep.removingAttachments].
  final int done;
  final int total;
}

enum AccountDeletionStage {
  offline,

  /// The sign-in ended (refresh rejected, or no user after refreshing).
  /// Nothing was deleted.
  sessionEnded,
  attachments,
  account,
  localWipe,
}

sealed class AccountDeletionResult {
  const AccountDeletionResult();
}

final class AccountDeleted extends AccountDeletionResult {
  const AccountDeleted();
}

final class AccountDeletionFailed extends AccountDeletionResult {
  const AccountDeletionFailed(
    this.stage,
    this.message, {
    this.failedAttachments = 0,
  });

  final AccountDeletionStage stage;

  /// Short human-readable cause.
  final String message;

  /// Non-zero only for [AccountDeletionStage.attachments] when files failed
  /// to delete. Zero with stage `attachments` means the attachment list
  /// could not be read; nothing was deleted.
  final int failedAttachments;
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
    this.rpcTimeout = const Duration(seconds: 60),
    this.requestTimeout = const Duration(seconds: 30),
  })  : _session = session,
        _backend = backend,
        _sync = sync,
        _localStorageKeys = localStorageKeys,
        _deleteObject = deleteObject,
        _signOut = signOut,
        _wipeLocal = wipeLocal;

  final SessionSource _session;
  final AccountDeletionBackend _backend;
  final SyncPause _sync;
  final Future<List<String>> Function() _localStorageKeys;
  final Future<void> Function(String objectKey) _deleteObject;
  final Future<void> Function() _signOut;
  final Future<void> Function() _wipeLocal;

  /// Limit on the `delete_my_account` call. Above the function's own 50 s
  /// `statement_timeout`, so by the time it fires the server has either
  /// committed or given up; the existence probe then tells which.
  final Duration rpcTimeout;

  /// Limit on each attachment delete attempt and on the existence probe.
  /// A timed-out delete counts as a failed attempt.
  final Duration requestTimeout;

  Future<AccountDeletionResult>? _inFlight;

  /// Runs the flow. A second call while one is running returns the same
  /// future. Never throws; failures come back as [AccountDeletionFailed].
  Future<AccountDeletionResult> deleteAccount({
    void Function(AccountDeletionProgress)? onProgress,
  }) {
    return _inFlight ??= _run(onProgress).whenComplete(() => _inFlight = null);
  }

  Future<AccountDeletionResult> _run(
    void Function(AccountDeletionProgress)? onProgress,
  ) async {
    // A throwing UI callback must never abort the flow: by the time the
    // later steps report, the account may already be deleted.
    void report(AccountDeletionProgress p) {
      try {
        onProgress?.call(p);
      } catch (e) {
        debugPrint('AccountDeleter: onProgress threw (ignored): $e');
      }
    }

    report(const AccountDeletionProgress(AccountDeletionStep.checking));
    try {
      await _session.refreshSession();
    } on AuthRetryableFetchException catch (e) {
      return AccountDeletionFailed(AccountDeletionStage.offline, _describe(e));
    } on AuthException catch (e) {
      // gotrue removes the session itself on any non-retryable refresh
      // error, so the user really is signed out now.
      return AccountDeletionFailed(
        AccountDeletionStage.sessionEnded,
        _describe(e),
      );
    } catch (e) {
      return AccountDeletionFailed(AccountDeletionStage.offline, _describe(e));
    }
    final uid = _session.currentSession?.user.id;
    if (uid == null || uid.isEmpty) {
      return const AccountDeletionFailed(
        AccountDeletionStage.sessionEnded,
        'No signed-in user after refreshing the session',
      );
    }

    await _sync.pause();
    try {
      // Collect keys: server first, then local-only, first-seen order. Only
      // keys under this user's prefix: the Worker refuses any other key, so
      // passing one would fail the sweep on every retry.
      final prefix = 'attachments/$uid/';
      final List<String> keys;
      try {
        final server = await _backend.listStorageKeys();
        final local = await _localStorageKeys();
        keys = [
          for (final k in {...server, ...local})
            if (k.startsWith(prefix)) k,
        ];
      } catch (e) {
        return AccountDeletionFailed(
          AccountDeletionStage.attachments,
          _describe(e),
        );
      }

      // Delete files. Sequential; each key gets at most two attempts.
      report(AccountDeletionProgress(
        AccountDeletionStep.removingAttachments,
        total: keys.length,
      ));
      var failed = 0;
      Object? lastError;
      for (var i = 0; i < keys.length; i++) {
        try {
          try {
            await _deleteObject(keys[i]).timeout(requestTimeout);
          } catch (_) {
            await _deleteObject(keys[i]).timeout(requestTimeout);
          }
        } catch (e) {
          failed++;
          lastError = e;
          debugPrint('AccountDeleter: failed to delete ${keys[i]}: $e');
        }
        report(AccountDeletionProgress(
          AccountDeletionStep.removingAttachments,
          done: i + 1,
          total: keys.length,
        ));
      }
      if (failed > 0) {
        return AccountDeletionFailed(
          AccountDeletionStage.attachments,
          _describe(lastError!),
          failedAttachments: failed,
        );
      }

      report(const AccountDeletionProgress(AccountDeletionStep.deletingAccount));
      try {
        await _backend.deleteAccount().timeout(rpcTimeout);
      } catch (e) {
        // The delete may have committed with only the response lost. If
        // the server says the user is gone, finish the flow; if it says
        // the user is there, or cannot tell, report the failure.
        if (await _accountGone()) {
          debugPrint('AccountDeleter: rpc failed but the account is gone '
              '(continuing): $e');
        } else {
          return AccountDeletionFailed(
            AccountDeletionStage.account,
            _describe(e),
          );
        }
      }

      report(const AccountDeletionProgress(AccountDeletionStep.clearingDevice));
      try {
        await _signOut();
      } catch (e) {
        debugPrint('AccountDeleter: sign-out failed (ignored): $e');
      }
      try {
        await _wipeLocal();
      } catch (e) {
        return AccountDeletionFailed(
          AccountDeletionStage.localWipe,
          _describe(e),
        );
      }
      return const AccountDeleted();
    } finally {
      await _sync.resume();
    }
  }

  /// True only when the server positively says the user is gone. A probe
  /// that fails or times out counts as "still there".
  Future<bool> _accountGone() async {
    try {
      return !await _backend.accountExists().timeout(requestTimeout);
    } catch (e) {
      debugPrint('AccountDeleter: account probe failed: $e');
      return false;
    }
  }

  /// Short cause for [AccountDeletionFailed.message]: the server's own
  /// message where there is one, rather than the exception's dump.
  static String _describe(Object e) => switch (e) {
        PostgrestException(:final message) => message,
        AuthException(:final message) => message,
        _ => e.toString(),
      };
}
