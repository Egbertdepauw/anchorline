/// Deletes the R2 objects of attachments that were soft-deleted a while ago.
///
/// Soft-deleting an attachment (5-second UNDO window) leaves its object in
/// R2, where it keeps counting against the account's storage limit. This
/// sweep gives deleted rows a grace period ([purgeDeleted]'s `minAge`), then
/// deletes the object through the Worker's idempotent `/delete` route and
/// marks the row purged (`upload_state = 3`) so it is not swept again and
/// can no longer be restored.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../data/db/dive_attachments_dao.dart';

class AttachmentPurger {
  AttachmentPurger({
    required DiveAttachmentsDao dao,
    required Future<void> Function(String objectKey) deleteObject,
    DateTime Function()? now,
  })  : _dao = dao,
        _deleteObject = deleteObject,
        _now = now ?? DateTime.now;

  final DiveAttachmentsDao _dao;
  final Future<void> Function(String objectKey) _deleteObject;
  final DateTime Function() _now;

  Future<int>? _inFlight;
  Duration _inFlightMinAge = Duration.zero;

  /// Purges every file row soft-deleted at least [minAge] ago. Returns the
  /// number of rows marked purged. Each row is claimed (`markPurged`) before
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

  /// Whether any soft-deleted file row still has an R2 object to purge,
  /// ignoring the grace period. Soft-deletes the attachments of deleted
  /// dives first, as [purgeDeleted] does, so those count. `pending:` rows
  /// never reached R2 and free no bytes, so they don't count.
  Future<bool> hasPurgeable() async {
    await _dao.softDeleteUnderDeletedDives(now: _now());
    return (await _dao.listPurgeable(_now()))
        .any((r) => !r.storageKey.startsWith('pending:'));
  }

  Future<int> _run(Duration minAge) async {
    // Attachments of a deleted dive count as deleted too (#198). The
    // dive delete cascades now; this catches dives deleted before that.
    await _dao.softDeleteUnderDeletedDives(now: _now());
    final rows = await _dao.listPurgeable(_now().subtract(minAge));
    var purged = 0;
    for (final row in rows) {
      final key = row.storageKey;
      if (!await _dao.markPurged(row.id, expectedKey: key)) continue;
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
          );
          continue;
        }
      }
      purged++;
    }
    return purged;
  }
}
