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

  // ── OxygenCells ──────────────────────────────────────────────────────────

  Future<String> addCell({
    required int slot,
    String? label,
    DateTime? installedDate,
    String? notes,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = 'cell_${now}_$slot';
    await into(oxygenCells).insert(OxygenCellsCompanion.insert(
      id: id,
      slot: slot,
      label: Value(label),
      installedDate: Value(installedDate?.millisecondsSinceEpoch),
      notes: Value(notes),
      createdAt: now,
      updatedAt: now,
    ));
    return id;
  }

  Future<List<OxygenCell>> listCells() async {
    final rows = await (select(oxygenCells)
          ..where((t) => t.deletedAt.isNull()))
        .get();
    rows.sort((a, b) {
      if (a.retiredDate == null && b.retiredDate != null) return -1;
      if (a.retiredDate != null && b.retiredDate == null) return 1;
      if (a.retiredDate != null && b.retiredDate != null) {
        return b.retiredDate!.compareTo(a.retiredDate!);
      }
      return (b.installedDate ?? 0).compareTo(a.installedDate ?? 0);
    });
    return rows;
  }

  Future<OxygenCell?> getCell(String id) {
    return (select(oxygenCells)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> updateCell(
    String id, {
    int? slot,
    String? label,
    DateTime? installedDate,
    String? notes,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (update(oxygenCells)..where((t) => t.id.equals(id))).write(
      OxygenCellsCompanion(
        slot: slot == null ? const Value.absent() : Value(slot),
        label: Value(label),
        installedDate: Value(installedDate?.millisecondsSinceEpoch),
        notes: Value(notes),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> retireCell(String id, {required DateTime retiredAt}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (update(oxygenCells)..where((t) => t.id.equals(id))).write(
      OxygenCellsCompanion(
        retiredDate: Value(retiredAt.millisecondsSinceEpoch),
        updatedAt: Value(now),
      ),
    );
  }

  /// Deletes the cell only if no dives can be attributed to its
  /// `[installedDate, retiredDate)` window:
  ///
  /// - If both `installedDate` and `retiredDate` are null, the cell has
  ///   no window to attribute dives to and is deleted.
  /// - If `installedDate` is null but `retiredDate` is set, the upper
  ///   bound alone is used (any dive before retire could have used the cell).
  /// - Otherwise the inclusive-exclusive window check applies.
  ///
  /// Returns true on delete, false if attributable dives exist.
  ///
  /// Uses the real `Dives` schema column `startTime` (not the speculative
  /// `startTimeUtc` that appeared in the plan's first draft).
  Future<bool> deleteCellIfUnused(String id) async {
    final cell = await getCell(id);
    if (cell == null) return false;

    final installed = cell.installedDate;
    final retired = cell.retiredDate;

    // No window known and no retire date → cell has no possible attributable dives.
    if (installed == null && retired == null) {
      await (delete(oxygenCells)..where((t) => t.id.equals(id))).go();
      return true;
    }

    final overlapping = await (select(db.dives)
          ..where((t) {
            Expression<bool> expr = const Constant(true);
            if (installed != null) {
              expr = expr & t.startTime.isBiggerOrEqualValue(installed);
            }
            if (retired != null) {
              expr = expr & t.startTime.isSmallerThanValue(retired);
            }
            return expr;
          })
          ..limit(1))
        .get();
    if (overlapping.isNotEmpty) return false;

    await (delete(oxygenCells)..where((t) => t.id.equals(id))).go();
    return true;
  }
}
