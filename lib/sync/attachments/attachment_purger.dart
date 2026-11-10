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

  /// Purges every file row soft-deleted at least [minAge] ago. Returns the
  /// number of rows marked purged. A failed delete leaves that row unpurged
  /// (the next run retries it) and does not stop the others. Concurrent
  /// calls share one in-flight run.
  Future<int> purgeDeleted({Duration minAge = const Duration(hours: 24)}) {
    return _inFlight ??= _run(minAge).whenComplete(() => _inFlight = null);
  }

  /// Whether any soft-deleted file row still has an R2 object to purge,
  /// ignoring the grace period.
  Future<bool> hasPurgeable() async {
    return (await _dao.listPurgeable(_now())).isNotEmpty;
  }

  Future<int> _run(Duration minAge) async {
    final rows = await _dao.listPurgeable(_now().subtract(minAge));
    var purged = 0;
    for (final row in rows) {
      // `pending:<id>` rows never reached R2; nothing to delete.
      if (!row.storageKey.startsWith('pending:')) {
        try {
          await _deleteObject(row.storageKey);
        } catch (e) {
          debugPrint('Attachment purge: delete of ${row.storageKey} failed: $e');
          continue;
        }
      }
      await _dao.markPurged(row.id);
      purged++;
    }
    return purged;
  }
}
