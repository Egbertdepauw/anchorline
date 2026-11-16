import 'package:powersync/powersync.dart';

import '../../diagnostics/sentry_redaction.dart';
import 'powersync_schema.dart';

/// Reports an upload the server refused with 42501 to Sentry. Tags are fixed
/// strings: the table (only if it is a known synced table), the op type and
/// the SQLSTATE. Ids and message text stay out; a `dc_<serial>` id carries a
/// serial number.
Future<void> reportUploadPermissionDenied(
    String table, UpdateType opType, Object error, StackTrace stack) {
  return captureRedactedException(error, stack, tags: {
    'sync.table': kSyncedTableNames.contains(table) ? table : 'other',
    'sync.op': opType.name,
    'sync.sqlstate': '42501',
  });
}
