/// Runs the in-app "Delete account" flow (spec 2026-11-08, section 6.2).
///
/// The order is load-bearing:
///
/// 1. Refresh the session (doubles as the online check).
/// 2. Pause sync, so queued uploads cannot race the delete.
/// 3. Collect attachment keys (server list plus this device's list).
/// 4. Delete the attachment files from R2.
/// 5. Delete the account (Postgres function; every cloud row cascades).
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

  /// Pages through [page] (inclusive `from`/`to` row indexes) until a page
  /// comes back shorter than [pageSize]. PostgREST caps a response at 1000
  /// rows by default, hence the loop.
  @visibleForTesting
  static Future<List<String>> fetchAllPages(
    Future<List<String>> Function(int from, int to) page, {
    int pageSize = 1000,
  }) async {
    final all = <String>[];
    var from = 0;
    while (true) {
      final chunk = await page(from, from + pageSize - 1);
      all.addAll(chunk);
      if (chunk.length < pageSize) break;
      from += pageSize;
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

enum AccountDeletionStage { offline, attachments, account, localWipe }

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

  /// Non-zero only for [AccountDeletionStage.attachments].
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
    void report(AccountDeletionProgress p) => onProgress?.call(p);

    report(const AccountDeletionProgress(AccountDeletionStep.checking));
    try {
      await _session.refreshSession();
    } catch (e) {
      return AccountDeletionFailed(AccountDeletionStage.offline, '$e');
    }

    await _sync.pause();
    try {
      // Collect keys: server first, then local-only, first-seen order.
      final List<String> keys;
      try {
        final server = await _backend.listStorageKeys();
        final local = await _localStorageKeys();
        keys = {...server, ...local}.toList();
      } catch (e) {
        return AccountDeletionFailed(AccountDeletionStage.attachments, '$e');
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
            await _deleteObject(keys[i]);
          } catch (_) {
            await _deleteObject(keys[i]);
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
          '$lastError',
          failedAttachments: failed,
        );
      }

      report(const AccountDeletionProgress(AccountDeletionStep.deletingAccount));
      try {
        await _backend.deleteAccount();
      } catch (e) {
        return AccountDeletionFailed(AccountDeletionStage.account, '$e');
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
        return AccountDeletionFailed(AccountDeletionStage.localWipe, '$e');
      }
      return const AccountDeleted();
    } finally {
      await _sync.resume();
    }
  }
}
