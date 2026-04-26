/// Data Access Object for equipment-view tables: dive computers, oxygen
/// cells, scrubber sessions, cylinders, and pressure-channel mappings.
///
/// Uses the `DriftAccessor` pattern so that table accessors (e.g.
/// `diveComputers`) are available directly on the DAO via the generated
/// `_$EquipmentDaoMixin`.
library;

import 'package:drift/drift.dart';

import 'database.dart';
import 'tables.dart';

part 'equipment_dao.g.dart';

@DriftAccessor(tables: [
  DiveComputers,
  OxygenCells,
  ScrubberSessions,
  Cylinders,
  PressureMappings,
])
class EquipmentDao extends DatabaseAccessor<AppDatabase>
    with _$EquipmentDaoMixin {
  EquipmentDao(super.db);

  // ── DiveComputers ────────────────────────────────────────────────────────

  /// Insert or update by `serial`. Preserves user-set `nickname` on update.
  /// Returns the resulting computer's primary-key id.
  Future<String> upsertDiveComputer({
    required int serial,
    required int model,
    int? firmwareVersion,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await (select(diveComputers)
          ..where((t) => t.serial.equals(serial)))
        .getSingleOrNull();

    if (existing == null) {
      final id = 'dc_${serial.toRadixString(16)}';
      await into(diveComputers).insert(DiveComputersCompanion.insert(
        id: id,
        serial: serial,
        model: model,
        firmwareVersion: Value(firmwareVersion),
        createdAt: now,
        updatedAt: now,
      ));
      return id;
    }

    await (update(diveComputers)..where((t) => t.id.equals(existing.id))).write(
      DiveComputersCompanion(
        model: Value(model),
        firmwareVersion: Value(firmwareVersion),
        updatedAt: Value(now),
      ),
    );
    return existing.id;
  }

  Future<List<DiveComputer>> listDiveComputers() {
    return (select(diveComputers)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
  }

  Future<void> setComputerNickname(String id, String? nickname) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (update(diveComputers)..where((t) => t.id.equals(id))).write(
      DiveComputersCompanion(
        nickname: Value(nickname),
        updatedAt: Value(now),
      ),
    );
  }

  /// Most recent dives imported from this computer (by `dcSerial`).
  Future<List<Dive>> recentImportsForComputer(int serial, {int limit = 10}) {
    return (select(db.dives)
          ..where((t) => t.dcSerial.equals(serial))
          ..orderBy([(t) => OrderingTerm.desc(t.startTime)])
          ..limit(limit))
        .get();
  }
}
