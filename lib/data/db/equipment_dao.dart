/// Data Access Object for equipment-view tables: dive computers, oxygen
/// cells, scrubber sessions, cylinders, and pressure-channel mappings.
///
/// Uses the `DriftAccessor` pattern so that table accessors (e.g.
/// `diveComputers`) are available directly on the DAO via the generated
/// `_$EquipmentDaoMixin`.
library;

import 'package:drift/drift.dart';

import '../../analysis/cell_health.dart';
import '../models/equipment.dart' show CylinderRole, SlotInUseException;
import '../sample_codec/column_packer.dart';
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
    await _assertSlotAvailable(slot);
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

  Future<void> _assertSlotAvailable(int slot, {String? excludingId}) async {
    final query = select(oxygenCells)
      ..where((t) =>
          t.slot.equals(slot) &
          t.retiredDate.isNull() &
          t.deletedAt.isNull());
    if (excludingId != null) {
      query.where((t) => t.id.equals(excludingId).not());
    }
    final conflict = await query.getSingleOrNull();
    if (conflict != null) {
      throw SlotInUseException(
        slot: slot,
        otherCellId: conflict.id,
        otherLabel: conflict.label,
      );
    }
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

  Future<Map<int, OxygenCell>> activeCellsAt(DateTime t) async {
    final ms = t.millisecondsSinceEpoch;
    final rows = await (select(oxygenCells)
          ..where((c) =>
              c.deletedAt.isNull() &
              c.installedDate.isNotNull() &
              c.installedDate.isSmallerOrEqualValue(ms) &
              (c.retiredDate.isNull() | c.retiredDate.isBiggerThanValue(ms))))
        .get();
    final out = <int, OxygenCell>{};
    for (final c in rows) {
      final existing = out[c.slot];
      if (existing == null ||
          (c.installedDate ?? 0) > (existing.installedDate ?? 0)) {
        out[c.slot] = c;
      }
    }
    return out;
  }

  Future<void> updateCell(
    String id, {
    int? slot,
    String? label,
    Value<DateTime?>? installedDate,
    String? notes,
  }) async {
    if (slot != null) {
      await _assertSlotAvailable(slot, excludingId: id);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await (update(oxygenCells)..where((t) => t.id.equals(id))).write(
      OxygenCellsCompanion(
        slot: slot == null ? const Value.absent() : Value(slot),
        label: label == null ? const Value.absent() : Value(label),
        installedDate: installedDate == null
            ? const Value.absent()
            : Value(installedDate.value?.millisecondsSinceEpoch),
        notes: notes == null ? const Value.absent() : Value(notes),
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
              expr = expr & t.startTime.isBiggerOrEqualValue(installed ~/ 1000);
            }
            if (retired != null) {
              expr = expr & t.startTime.isSmallerThanValue(retired ~/ 1000);
            }
            return expr;
          })
          ..limit(1))
        .get();
    if (overlapping.isNotEmpty) return false;

    await (delete(oxygenCells)..where((t) => t.id.equals(id))).go();
    return true;
  }

  // ── Cell aggregation ─────────────────────────────────────────────────────

  /// Per-dive surface-mV time series for a cell, across all dives in the
  /// cell's [installedDate, retiredDate) window.
  ///
  /// "Surface mV" = mean of `cellMv[slot]` over samples where `depthM < 1.0`
  /// AND `cellMv >= 5.0` (voted-out heuristic). Dives with no qualifying
  /// samples are omitted. Slot is 1-based on the table; cellMv channels are
  /// 0-based in the sample columns (slot 1 → cellMv0, etc).
  Future<List<({DateTime date, double mv, String diveId})>>
      surfaceMvSeriesForCell(String cellId) async {
    final cell = await getCell(cellId);
    if (cell == null) return const [];

    final mvCol = cell.slot - 1; // 1→0, 2→1, 3→2
    if (mvCol < 0 || mvCol > 2) return const [];

    final query = select(db.dives);
    if (cell.installedDate != null) {
      query.where(
          (t) => t.startTime.isBiggerOrEqualValue(cell.installedDate! ~/ 1000));
    }
    if (cell.retiredDate != null) {
      query.where(
          (t) => t.startTime.isSmallerThanValue(cell.retiredDate! ~/ 1000));
    }
    query.orderBy([(t) => OrderingTerm.asc(t.startTime)]);
    final dives = await query.get();
    if (dives.isEmpty) return const [];

    final samplesById = <String, DiveSample>{
      for (final s in await (select(db.diveSamples)
                ..where((t) => t.diveId.isIn(dives.map((d) => d.id))))
              .get())
        s.diveId: s,
    };

    final out = <({DateTime date, double mv, String diveId})>[];
    for (final dive in dives) {
      final sample = samplesById[dive.id];
      if (sample == null) continue;
      final mv = _computeSurfaceMv(sample, mvCol);
      if (mv == null) continue;
      out.add((
        date: DateTime.fromMillisecondsSinceEpoch(dive.startTime * 1000),
        mv: mv,
        diveId: dive.id,
      ));
    }
    return out;
  }

  Future<CellHealth> evaluateHealthForCell(String cellId,
      {DateTime? now}) async {
    final cell = await getCell(cellId);
    if (cell == null) {
      return CellHealth(
        ageMonths: null,
        diveCount: 0,
        mvStatus: CellMvStatus.insufficientData,
        baselinePeakMv: null,
        recentPeakMv: null,
      );
    }

    final mvCol = cell.slot - 1;
    final installedDate = cell.installedDate == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(cell.installedDate!);

    final divePeaks = <({DateTime start, double peakMv})>[];
    if (mvCol >= 0 && mvCol <= 2) {
      final query = select(db.dives);
      if (cell.installedDate != null) {
        query.where((t) =>
            t.startTime.isBiggerOrEqualValue(cell.installedDate! ~/ 1000));
      }
      if (cell.retiredDate != null) {
        query.where(
            (t) => t.startTime.isSmallerThanValue(cell.retiredDate! ~/ 1000));
      }
      query.orderBy([(t) => OrderingTerm.asc(t.startTime)]);
      final dives = await query.get();
      if (dives.isNotEmpty) {
        final samplesById = <String, DiveSample>{
          for (final s in await (select(db.diveSamples)
                    ..where((t) => t.diveId.isIn(dives.map((d) => d.id))))
                  .get())
            s.diveId: s,
        };
        for (final dive in dives) {
          final sample = samplesById[dive.id];
          if (sample == null) continue;
          final peak = _peakMvForSlot(sample, mvCol);
          if (peak == null) continue;
          divePeaks.add((
            start:
                DateTime.fromMillisecondsSinceEpoch(dive.startTime * 1000),
            peakMv: peak,
          ));
        }
      }
    }

    return evaluateCellHealth(
      now: now ?? DateTime.now(),
      installedDate: installedDate,
      divePeaks: divePeaks,
    );
  }

  double? _peakMvForSlot(DiveSample sample, int mvCol) {
    final mvBlob = switch (mvCol) {
      0 => sample.cellMv0Blob,
      1 => sample.cellMv1Blob,
      _ => sample.cellMv2Blob,
    };
    final mvs = ColumnPacker.unpackFloat32(mvBlob, sample.sampleCount);
    var peak = double.negativeInfinity;
    var any = false;
    for (var i = 0; i < sample.sampleCount; i++) {
      final v = mvs[i];
      if (v < 5.0) continue;
      if (v > peak) peak = v;
      any = true;
    }
    return any ? peak : null;
  }

  double? _computeSurfaceMv(DiveSample sample, int mvCol) {
    final depths =
        ColumnPacker.unpackFloat32(sample.depthBlob, sample.sampleCount);
    final mvBlob = switch (mvCol) {
      0 => sample.cellMv0Blob,
      1 => sample.cellMv1Blob,
      _ => sample.cellMv2Blob,
    };
    final mvs = ColumnPacker.unpackFloat32(mvBlob, sample.sampleCount);
    var sum = 0.0;
    var count = 0;
    for (var i = 0; i < sample.sampleCount; i++) {
      if (depths[i] >= 1.0) continue;
      final v = mvs[i];
      if (v < 5.0) continue;
      sum += v;
      count++;
    }
    return count == 0 ? null : sum / count;
  }

  // ── ScrubberSessions ─────────────────────────────────────────────────────

  Future<String> addScrubberSession({
    required DateTime startedDate,
    String? mediaType,
    String? notes,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = 'scrub_$now';
    await into(scrubberSessions).insert(ScrubberSessionsCompanion.insert(
      id: id,
      startedDate: Value(startedDate.millisecondsSinceEpoch),
      mediaType: Value(mediaType),
      notes: Value(notes),
      createdAt: now,
      updatedAt: now,
    ));
    return id;
  }

  Future<List<ScrubberSession>> listScrubberSessions() async {
    final rows = await (select(scrubberSessions)
          ..where((t) => t.deletedAt.isNull()))
        .get();
    // Active (totalMinutes IS NULL) first; closed sorted by startedDate desc.
    rows.sort((a, b) {
      if (a.totalMinutes == null && b.totalMinutes != null) return -1;
      if (a.totalMinutes != null && b.totalMinutes == null) return 1;
      return (b.startedDate ?? 0).compareTo(a.startedDate ?? 0);
    });
    return rows;
  }

  Future<ScrubberSession?> getScrubberSession(String id) {
    return (select(scrubberSessions)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> updateScrubberSession(
    String id, {
    DateTime? startedDate,
    String? mediaType,
    String? notes,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (update(scrubberSessions)..where((t) => t.id.equals(id))).write(
      ScrubberSessionsCompanion(
        startedDate: startedDate == null
            ? const Value.absent()
            : Value(startedDate.millisecondsSinceEpoch),
        mediaType: mediaType == null ? const Value.absent() : Value(mediaType),
        notes: notes == null ? const Value.absent() : Value(notes),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> closeScrubberSession(String id, {required DateTime endedAt}) async {
    final session = await getScrubberSession(id);
    if (session == null) return;
    final minutes = await accumulatedMinutesForSession(
      id,
      endBoundOverride: endedAt,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    await (update(scrubberSessions)..where((t) => t.id.equals(id))).write(
      ScrubberSessionsCompanion(
        totalMinutes: Value(minutes),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> deleteScrubberSession(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (update(scrubberSessions)..where((t) => t.id.equals(id))).write(
      ScrubberSessionsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// Forward-compatible hook called per imported dive. Currently a no-op
  /// when [scrubberResetAt] is null; once the parser surfaces a real reset
  /// timestamp this will close the open session and start a new one.
  Future<void> applyScrubberEvents({
    required DateTime? scrubberResetAt,
    required int dcSerial,
  }) async {
    if (scrubberResetAt == null) return;

    await db.transaction(() async {
      final open = await (select(scrubberSessions)
            ..where((t) =>
                t.deletedAt.isNull() & t.totalMinutes.isNull()))
          .get();
      for (final s in open) {
        await closeScrubberSession(s.id, endedAt: scrubberResetAt);
      }
      await addScrubberSession(startedDate: scrubberResetAt);
      // dcSerial reserved for a future migration that ties scrubber sessions
      // to a specific dive computer (multi-rig support).
      // ignore: unused_local_variable
      final _ = dcSerial;
    });
  }

  /// Sum of dive runtimes (in minutes) whose `startTime` falls in
  /// [session.startedDate, endBound) where `endBound` is the next session's
  /// `startedDate` (or [endBoundOverride] if the caller is closing the
  /// session). MVP fallback: dive runtime over-estimates by surface time;
  /// replace with per-sample scrubber-on time when the parser exposes it.
  ///
  /// Uses real `Dives` schema fields `startTime` and `durationSeconds`
  /// (NOT the speculative `startTimeUtc`/`runtimeSeconds`).
  Future<int> accumulatedMinutesForSession(
    String id, {
    DateTime? endBoundOverride,
  }) async {
    final session = await getScrubberSession(id);
    if (session == null || session.startedDate == null) return 0;

    int? endEpoch = endBoundOverride?.millisecondsSinceEpoch;
    if (endEpoch == null) {
      final later = await (select(scrubberSessions)
            ..where((t) =>
                t.deletedAt.isNull() &
                t.startedDate.isBiggerThanValue(session.startedDate!)))
          .get();
      if (later.isNotEmpty) {
        endEpoch = later
            .map((s) => s.startedDate!)
            .reduce((a, b) => a < b ? a : b);
      }
    }

    final dives = await (select(db.dives)
          ..where((t) {
            var expr = t.startTime
                .isBiggerOrEqualValue(session.startedDate! ~/ 1000);
            if (endEpoch != null) {
              expr = expr & t.startTime.isSmallerThanValue(endEpoch ~/ 1000);
            }
            return expr;
          }))
        .get();

    final totalSeconds =
        dives.fold<int>(0, (sum, d) => sum + d.durationSeconds);
    return totalSeconds ~/ 60;
  }

  // ── Cylinders ────────────────────────────────────────────────────────────

  Future<String> addCylinder({
    required String label,
    required String role,
    int? bailoutOrder,
    required double volumeLiters,
    required int workingPressureBar,
    String? gasMix,
    String? notes,
  }) async {
    if (!CylinderRole.all.contains(role)) {
      throw ArgumentError.value(role, 'role',
          'must be one of ${CylinderRole.all}');
    }
    final effectiveOrder =
        role == CylinderRole.bailout ? bailoutOrder : null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = 'cyl_${now}_$role';
    await into(cylinders).insert(CylindersCompanion.insert(
      id: id,
      label: label,
      role: role,
      bailoutOrder: Value(effectiveOrder),
      volumeLiters: volumeLiters,
      workingPressureBar: workingPressureBar,
      gasMix: Value(gasMix),
      notes: Value(notes),
      createdAt: now,
      updatedAt: now,
    ));
    return id;
  }

  Future<List<Cylinder>> listCylinders() async {
    final rows = await (select(cylinders)
          ..where((t) => t.deletedAt.isNull()))
        .get();
    // Sort by role group order, then bailoutOrder asc, then label asc.
    const roleOrder = {
      CylinderRole.oxygen: 0,
      CylinderRole.diluent: 1,
      CylinderRole.bailout: 2,
      CylinderRole.offboard: 3,
    };
    rows.sort((a, b) {
      final ra = roleOrder[a.role] ?? 99;
      final rb = roleOrder[b.role] ?? 99;
      if (ra != rb) return ra.compareTo(rb);
      final oa = a.bailoutOrder ?? 0;
      final ob = b.bailoutOrder ?? 0;
      if (oa != ob) return oa.compareTo(ob);
      return a.label.compareTo(b.label);
    });
    return rows;
  }

  Future<Cylinder?> getCylinder(String id) {
    return (select(cylinders)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> updateCylinder(
    String id, {
    String? label,
    String? role,
    int? bailoutOrder,
    double? volumeLiters,
    int? workingPressureBar,
    String? gasMix,
    String? notes,
  }) async {
    if (role != null && !CylinderRole.all.contains(role)) {
      throw ArgumentError.value(role, 'role');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    // If the role is being moved away from bailout, force-clear bailoutOrder.
    Value<int?> effectiveBailoutOrder;
    if (role != null && role != CylinderRole.bailout) {
      effectiveBailoutOrder = const Value(null);
    } else if (bailoutOrder != null) {
      effectiveBailoutOrder = Value(bailoutOrder);
    } else {
      effectiveBailoutOrder = const Value.absent();
    }
    await (update(cylinders)..where((t) => t.id.equals(id))).write(
      CylindersCompanion(
        label: label == null ? const Value.absent() : Value(label),
        role: role == null ? const Value.absent() : Value(role),
        bailoutOrder: effectiveBailoutOrder,
        volumeLiters:
            volumeLiters == null ? const Value.absent() : Value(volumeLiters),
        workingPressureBar: workingPressureBar == null
            ? const Value.absent()
            : Value(workingPressureBar),
        gasMix: gasMix == null ? const Value.absent() : Value(gasMix),
        notes: notes == null ? const Value.absent() : Value(notes),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> softDeleteCylinder(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (update(cylinders)..where((t) => t.id.equals(id))).write(
      CylindersCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  // ── PressureMappings ─────────────────────────────────────────────────────

  Future<List<PressureMapping>> listPressureMappings(String diveComputerId) {
    return (select(pressureMappings)
          ..where((t) =>
              t.diveComputerId.equals(diveComputerId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.channelIndex)]))
        .get();
  }

  Future<void> setPressureMapping({
    required String diveComputerId,
    required int channelIndex,
    required String? cylinderId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await into(pressureMappings).insertOnConflictUpdate(
      PressureMappingsCompanion.insert(
        diveComputerId: diveComputerId,
        channelIndex: channelIndex,
        cylinderId: Value(cylinderId),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Best-effort enumeration of pressure-channel indexes the device has
  /// logged. MVP returns channels that already have a mapping; a parser-
  /// side "infer from imports" lookup is a follow-up once the per-channel
  /// pressure series is known to surface in the sample blob.
  Future<List<int>> pressureChannelsSeenForComputer(
      String diveComputerId) async {
    final rows = await listPressureMappings(diveComputerId);
    return rows.map((r) => r.channelIndex).toList();
  }

  Future<void> seedStandardCcrCylinders() async {
    await addCylinder(
      label: 'O2',
      role: CylinderRole.oxygen,
      volumeLiters: 2.0,
      workingPressureBar: 207,
      gasMix: '100',
    );
    await addCylinder(
      label: 'Diluent',
      role: CylinderRole.diluent,
      volumeLiters: 3.0,
      workingPressureBar: 232,
    );
    await addCylinder(
      label: 'Bailout',
      role: CylinderRole.bailout,
      bailoutOrder: 1,
      volumeLiters: 7.0,
      workingPressureBar: 232,
    );
  }
}
