/// Data Access Object for import state persistence.
///
/// Tracks the last successfully imported dive fingerprint per dive computer
/// serial number, enabling incremental / resumable BLE imports.
library;

import 'package:drift/drift.dart';

import '../../devices/fingerprint_store.dart';
import 'database.dart';

/// DAO for reading and writing per-device import state.
class ImportStateDao implements FingerprintStore {
  final AppDatabase _db;

  ImportStateDao(this._db);

  @override
  Future<Map<String, Uint8List>> withPrefix(String prefix) =>
      fingerprintsWithPrefix(prefix);

  /// Every saved fingerprint whose key starts with [prefix], by key. The
  /// libdivecomputer keys are `libdc:<family>:<serial>`.
  Future<Map<String, Uint8List>> fingerprintsWithPrefix(String prefix) async {
    // LIKE treats `_` as a wildcard, so it only narrows the rows; the exact
    // prefix test is in Dart.
    final rows = await (_db.select(_db.importStates)
          ..where((t) => t.dcSerial.like('${prefix.replaceAll('%', '')}%')))
        .get();
    return {
      for (final r in rows)
        if (r.dcSerial.startsWith(prefix) && r.lastFingerprint != null)
          r.dcSerial: r.lastFingerprint!,
    };
  }

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
