/// Data Access Object for import state persistence.
///
/// Tracks the last successfully imported dive fingerprint per dive computer
/// serial number, enabling incremental / resumable BLE imports.
library;

import 'package:drift/drift.dart';

import 'database.dart';

/// DAO for reading and writing per-device import state.
class ImportStateDao {
  final AppDatabase _db;

  ImportStateDao(this._db);

  /// Returns the last successfully imported fingerprint for [dcSerial],
  /// or `null` if this device has never been imported from.
  Future<Uint8List?> getLastFingerprint(String dcSerial) async {
    final query = _db.select(_db.importStates)
      ..where((t) => t.dcSerial.equals(dcSerial));
    final row = await query.getSingleOrNull();
    return row?.lastFingerprint;
  }

  /// Persists [fingerprint] as the latest successfully imported fingerprint
  /// for [dcSerial], creating or replacing any existing record.
  Future<void> saveLastFingerprint(String dcSerial, Uint8List fingerprint) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.into(_db.importStates).insertOnConflictUpdate(
      ImportStatesCompanion.insert(
        dcSerial: dcSerial,
        lastFingerprint: Value(fingerprint),
        lastImportAt: Value(now),
      ),
    );
  }
}
