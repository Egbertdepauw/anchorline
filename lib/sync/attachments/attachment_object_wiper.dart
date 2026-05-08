/// Best-effort sweep that deletes every R2 object owned by the current
/// user before the cloud-data wipe runs.
///
/// Why "before": once [CloudDataWiper] removes the `dive_attachments`
/// rows from Postgres, PowerSync replicates those deletions down to
/// every device's local cache, and the [AttachmentObjectWiper] no
/// longer has a list of storage keys to delete. So this sweep must
/// run with the local cache still intact, which means: while the user
/// is signed in and before any DELETE round-trip to Postgres.
///
/// Why "best-effort": the Worker may be down, the network may flap,
/// or the JWT may rotate mid-sweep. Failures are logged but not
/// fatal — orphaned R2 objects cost a few cents/month and a future
/// scheduled cleanup task can compare bucket vs. table to reap them.
/// Failing the entire reset because R2 is unreachable would leave the
/// user stranded; the cloud-data wipe matters more.
library;

import 'package:flutter/foundation.dart';

import '../../data/db/dive_attachments_dao.dart';
import 'attachment_signer.dart';

class AttachmentObjectWiper {
  final DiveAttachmentsDao _dao;
  final AttachmentSigner _signer;

  AttachmentObjectWiper({
    required DiveAttachmentsDao dao,
    required AttachmentSigner signer,
  })  : _dao = dao,
        _signer = signer;

  /// Deletes every R2 object whose storage key is in the local
  /// `dive_attachments` cache. Returns the count of successful deletes.
  /// Logs each failure but never throws — see the library doc above.
  Future<int> wipeAllForCurrentUser() async {
    final keys = await _dao.listAllStorageKeys();
    var deleted = 0;
    for (final key in keys) {
      try {
        await _signer.deleteObject(objectKey: key);
        deleted++;
      } catch (e) {
        debugPrint('AttachmentObjectWiper: failed to delete $key: $e');
      }
    }
    return deleted;
  }
}
