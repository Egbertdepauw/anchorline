/// Deletes the R2 objects of attachments that were soft-deleted a while ago.
///
/// Soft-deleting an attachment (5-second UNDO window) leaves its object in
/// R2, where it keeps counting against the account's storage limit. This
/// sweep gives deleted rows a grace period ([purgeDeleted]'s `minAge`), then
/// deletes the object through the Worker's idempotent `/delete` route and
/// marks the row purged (`upload_state = 3`) so it is not swept again and
/// can no longer be restored.
///
/// The R2 delete can't be undone, so the sweep only runs once the local data
/// has caught up with the server ([AttachmentPurger]'s `syncCaughtUp`): a
/// device that missed a restore made elsewhere must not act on its stale
/// view of it (#201).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../data/db/dive_attachments_dao.dart';

class AttachmentPurger {
  AttachmentPurger({
    required DiveAttachmentsDao dao,
    required Future<void> Function(String objectKey) deleteObject,
    Future<bool> Function()? syncCaughtUp,
    DateTime Function()? now,
  })  : _dao = dao,
        _deleteObject = deleteObject,
        _syncCaughtUp = syncCaughtUp ?? _always,
        _now = now ?? DateTime.now;

  final DiveAttachmentsDao _dao;
  final Future<void> Function(String objectKey) _deleteObject;

  /// Resolves to whether the local data has caught up with the server (it
  /// may wait a little for that). Checked before a run and before each
  /// claim; a run stops as soon as it is false.
  final Future<bool> Function() _syncCaughtUp;
  final DateTime Function() _now;

  static Future<bool> _always() async => true;

  /// Attachments deleted with their dive, or live under a deleted dive, are
  /// never purged within this long of the dive delete, whatever `minAge`
  /// is. A dive UNDO on another device (5 s) would otherwise come back
  /// without them, and an older build's UNDO doesn't restore attachments at
  /// all. Ten minutes also absorbs small clock differences.
  static const diveUndoGuard = Duration(minutes: 10);

  /// The earlier of [cutoff] and [diveUndoGuard] before now.
  DateTime _diveCutoff(DateTime cutoff) {
    final guard = _now().subtract(diveUndoGuard);
    return cutoff.isBefore(guard) ? cutoff : guard;
  }

  Future<int>? _inFlight;
  Duration _inFlightMinAge = Duration.zero;

  /// Purges every file row soft-deleted at least [minAge] ago. Returns the
  /// number of rows marked purged; 0 without touching anything when the
  /// local data hasn't caught up with the server. Each row is claimed (`markPurged`) before
  /// its object is deleted, so a concurrent UNDO or upload can't lose data;
  /// a failed delete reverts the claim (the next run retries it) and does
  /// not stop the others. A call whose [minAge] is not shorter than the
  /// in-flight run's shares that run; a shorter one runs after it.
  Future<int> purgeDeleted({Duration minAge = const Duration(hours: 24)}) {
    final running = _inFlight;
    if (running == null) {
      _inFlightMinAge = minAge;
      return _inFlight = _run(minAge).whenComplete(() => _inFlight = null);
    }
    if (minAge >= _inFlightMinAge) return running;
    return running.then(
      (_) => purgeDeleted(minAge: minAge),
      onError: (Object _) => purgeDeleted(minAge: minAge),
    );
  }

  /// Whether any deleted file row still has an R2 object to purge, ignoring
  /// the grace period. Attachments of a deleted dive count too. `pending:`
  /// rows never reached R2 and free no bytes, so they don't count. Read-only.
  Future<bool> hasPurgeable() async {
    final now = _now();
    return (await _dao.listPurgeable(now, diveDeletedBefore: _diveCutoff(now)))
        .any((r) => !r.storageKey.startsWith('pending:'));
  }

  Future<int> _run(Duration minAge) async {
    if (!await _syncCaughtUp()) return 0;
    // Includes live attachments of a deleted dive (#198): an older build's
    // dive delete doesn't cascade. The claim re-checks the dive (#201).
    final cutoff = _now().subtract(minAge);
    final diveCutoff = _diveCutoff(cutoff);
    final rows =
        await _dao.listPurgeable(cutoff, diveDeletedBefore: diveCutoff);
    var purged = 0;
    for (final row in rows) {
      // Checked per row too: a run can outlive the freshness it started
      // with (the app sleeps mid-run, then resumes on stale data).
      if (!await _syncCaughtUp()) break;
      final key = row.storageKey;
      if (!await _dao.markPurged(
        row.id,
        expectedKey: key,
        deletedBefore: cutoff,
        diveDeletedBefore: diveCutoff,
      )) {
        continue;
      }
      // `pending:<id>` rows never reached R2; nothing to delete.
      if (!key.startsWith('pending:')) {
        try {
          await _deleteObject(key);
        } catch (e) {
          // The key holds the user id; log the attachment id instead.
          debugPrint('Attachment purge: delete for ${row.id} failed: $e');
          await _dao.revertPurge(
            row.id,
            expectedKey: key,
            previous: row.uploadState,
            previousDeletedAt: row.deletedAt,
          );
          continue;
        }
      }
      purged++;
    }
    return purged;
  }
}
