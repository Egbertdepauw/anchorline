/// Data Access Object for equipment-view tables: dive computers, oxygen
/// cells, scrubber sessions, cylinders, pressure-channel mappings, and
/// per-dive cylinder assignments.
///
/// Phase 2.3: hybrid backend. The six sync-eligible tables live in
/// PowerSync (raw SQL via the `PowerSyncDatabase` view). Analysis
/// methods that join with imported dive data still query Drift directly
/// — `recentImportsForComputer`, `surfaceMvSeriesForCell`, scrubber
/// minute accumulation. The DAO holds both database handles and stitches
/// the two halves in Dart.
///
/// Drift row types (`Cylinder`, `OxygenCell`, etc.) are kept as the
/// public API surface so the existing UI/notifier callers don't change;
/// internally they're rebuilt from PowerSync `Map<String, dynamic>` rows.
library;
import 'package:drift/drift.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../../analysis/cell_health.dart';
import '../../sync/cloud/ccrlogger_backend_connector.dart' show SessionSource;
import '../models/equipment.dart' show CylinderRole, SlotInUseException;
import '../sample_codec/column_packer.dart';
import 'database.dart';

class EquipmentDao {
  final AppDatabase _drift;
  final PowerSyncDatabase _ps;
  final SessionSource _session;

  EquipmentDao(this._drift, this._ps, this._session);

  String? get _ownerId => _session.currentSession?.user.id;

  // ── DiveCylinders (per-dive gas-mix → cylinder mapping) ─────────────────
  //
  // Composite Drift PK (dive_id, gas_mix_index); synthesized cloud id is
  // "<dive_id>:<gas_mix_index>".

  Future<List<DiveCylinder>> listCylindersForDive(String diveId) async {
    final rows = await _ps.getAll(
      'SELECT * FROM dive_cylinders '
      'WHERE dive_id = ? AND deleted_at IS NULL '
      'ORDER BY gas_mix_index ASC',
      [diveId],
    );
    return rows.map(_rowToDiveCylinder).toList();
  }

  Future<void> setDiveCylinder(
      String diveId, int gasMixIndex, String? cylinderId) async {
    await _ps.writeTransaction((tx) async {
      await _upsertDiveCylinderTx(tx, diveId, gasMixIndex, cylinderId);
    });
  }

  Future<void> setDiveCylinders(
    String diveId,
    List<({int gasMixIndex, String? cylinderId})> mappings,
  ) async {
    await _ps.writeTransaction((tx) async {
      for (final m in mappings) {
        await _upsertDiveCylinderTx(tx, diveId, m.gasMixIndex, m.cylinderId);
      }
    });
  }

  Future<void> _upsertDiveCylinderTx(
    dynamic tx,
    String diveId,
    int gasMixIndex,
    String? cylinderId,
  ) async {
    final id = '$diveId:$gasMixIndex';
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await tx.getOptional(
      'SELECT version FROM dive_cylinders WHERE id = ?',
      [id],
    );
    if (existing == null) {
      await tx.execute(
        'INSERT INTO dive_cylinders '
        '(id, owner_id, dive_id, gas_mix_index, cylinder_id, '
        'created_at, updated_at, deleted_at, version, sync_status) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [id, _ownerId, diveId, gasMixIndex, cylinderId, now, now, null, 1, 0],
      );
    } else {
      final newVersion = (existing['version'] as int? ?? 0) + 1;
      await tx.execute(
        'UPDATE dive_cylinders SET '
        'owner_id = ?, cylinder_id = ?, updated_at = ?, version = ? '
        'WHERE id = ?',
        [_ownerId, cylinderId, now, newVersion, id],
      );
    }
  }

  // ── DiveComputers ────────────────────────────────────────────────────────

  /// Insert or update by `serial`. Preserves user-set `nickname` on update.
  /// Returns the resulting computer's primary-key id.
  Future<String> upsertDiveComputer({
    required int serial,
    required int model,
    int? firmwareVersion,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return await _ps.writeTransaction<String>((tx) async {
      final existing = await tx.getOptional(
        'SELECT id, version FROM dive_computers WHERE serial = ?',
        [serial],
      );
      if (existing == null) {
        final id = 'dc_${serial.toRadixString(16)}';
        await tx.execute(
          'INSERT INTO dive_computers '
          '(id, owner_id, serial, model, firmware_version, nickname, '
          'created_at, updated_at, deleted_at, version, sync_status) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [id, _ownerId, serial, model, firmwareVersion, null,
            now, now, null, 1, 0],
        );
        return id;
      }
      final id = existing['id'] as String;
      final newVersion = (existing['version'] as int? ?? 0) + 1;
      await tx.execute(
        'UPDATE dive_computers SET '
        'owner_id = ?, model = ?, firmware_version = ?, '
        'updated_at = ?, version = ? '
        'WHERE id = ?',
        [_ownerId, model, firmwareVersion, now, newVersion, id],
      );
      return id;
    });
  }

  Future<List<DiveComputer>> listDiveComputers() async {
    final rows = await _ps.getAll(
      'SELECT * FROM dive_computers '
      'WHERE deleted_at IS NULL '
      'ORDER BY updated_at DESC',
    );
    return rows.map(_rowToDiveComputer).toList();
  }

  Future<DiveComputer?> getDiveComputerBySerial(int serial) async {
    final row = await _ps.getOptional(
      'SELECT * FROM dive_computers WHERE serial = ?',
      [serial],
    );
    return row == null ? null : _rowToDiveComputer(row);
  }

  Future<void> setComputerNickname(String id, String? nickname) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _ps.writeTransaction((tx) async {
      final existing = await tx.getOptional(
        'SELECT version FROM dive_computers WHERE id = ?',
        [id],
      );
      if (existing == null) return;
      final newVersion = (existing['version'] as int? ?? 0) + 1;
      await tx.execute(
        'UPDATE dive_computers SET '
        'owner_id = ?, nickname = ?, updated_at = ?, version = ? '
        'WHERE id = ?',
        [_ownerId, nickname, now, newVersion, id],
      );
    });
  }

  /// Most recent dives imported from this computer (by `dcSerial`).
  /// Stays on Drift — Dives are not sync-eligible.
  Future<List<Dive>> recentImportsForComputer(int serial, {int limit = 10}) {
    return (_drift.select(_drift.dives)
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
    await _ps.writeTransaction((tx) async {
      await _assertSlotAvailableTx(tx, slot);
      await tx.execute(
        'INSERT INTO oxygen_cells '
        '(id, owner_id, slot, label, installed_date, retired_date, notes, '
        'created_at, updated_at, deleted_at, version, sync_status) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [id, _ownerId, slot, label, installedDate?.millisecondsSinceEpoch,
          null, notes, now, now, null, 1, 0],
      );
    });
    return id;
  }

  Future<void> _assertSlotAvailableTx(dynamic tx, int slot,
      {String? excludingId}) async {
    final params = <Object?>[slot];
    var sql = 'SELECT id, label FROM oxygen_cells '
        'WHERE slot = ? AND retired_date IS NULL AND deleted_at IS NULL';
    if (excludingId != null) {
      sql += ' AND id != ?';
      params.add(excludingId);
    }
    sql += ' LIMIT 1';
    final conflict = await tx.getOptional(sql, params);
    if (conflict != null) {
      throw SlotInUseException(
        slot: slot,
        otherCellId: conflict['id'] as String,
        otherLabel: conflict['label'] as String?,
      );
    }
  }

  Future<List<OxygenCell>> listCells() async {
    final rows = await _ps.getAll(
      'SELECT * FROM oxygen_cells WHERE deleted_at IS NULL',
    );
    final cells = rows.map(_rowToOxygenCell).toList();
    cells.sort((a, b) {
      if (a.retiredDate == null && b.retiredDate != null) return -1;
      if (a.retiredDate != null && b.retiredDate == null) return 1;
      if (a.retiredDate != null && b.retiredDate != null) {
        return b.retiredDate!.compareTo(a.retiredDate!);
      }
      return (b.installedDate ?? 0).compareTo(a.installedDate ?? 0);
    });
    return cells;
  }

  Future<OxygenCell?> getCell(String id) async {
    final row = await _ps.getOptional(
      'SELECT * FROM oxygen_cells WHERE id = ?',
      [id],
    );
    return row == null ? null : _rowToOxygenCell(row);
  }

  Future<Map<int, OxygenCell>> activeCellsAt(DateTime t) async {
    final ms = t.millisecondsSinceEpoch;
    final rows = await _ps.getAll(
      'SELECT * FROM oxygen_cells '
      'WHERE deleted_at IS NULL '
      'AND installed_date IS NOT NULL '
      'AND installed_date <= ? '
      'AND (retired_date IS NULL OR retired_date > ?)',
      [ms, ms],
    );
    final out = <int, OxygenCell>{};
    for (final r in rows) {
      final c = _rowToOxygenCell(r);
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
    final now = DateTime.now().millisecondsSinceEpoch;
    await _ps.writeTransaction((tx) async {
      if (slot != null) {
        await _assertSlotAvailableTx(tx, slot, excludingId: id);
      }
      final existing = await tx.getOptional(
        'SELECT * FROM oxygen_cells WHERE id = ?',
        [id],
      );
      if (existing == null) return;
      final newVersion = (existing['version'] as int? ?? 0) + 1;
      final newSlot = slot ?? existing['slot'] as int;
      final newLabel = label ?? existing['label'] as String?;
      final newInstalled = installedDate == null
          ? existing['installed_date'] as int?
          : installedDate.value?.millisecondsSinceEpoch;
      final newNotes = notes ?? existing['notes'] as String?;
      await tx.execute(
        'UPDATE oxygen_cells SET '
        'owner_id = ?, slot = ?, label = ?, installed_date = ?, notes = ?, '
        'updated_at = ?, version = ? '
        'WHERE id = ?',
        [_ownerId, newSlot, newLabel, newInstalled, newNotes,
          now, newVersion, id],
      );
    });
  }

  Future<void> retireCell(String id, {required DateTime retiredAt}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _ps.writeTransaction((tx) async {
      final existing = await tx.getOptional(
        'SELECT version FROM oxygen_cells WHERE id = ?',
        [id],
      );
      if (existing == null) return;
      final newVersion = (existing['version'] as int? ?? 0) + 1;
      await tx.execute(
        'UPDATE oxygen_cells SET '
        'owner_id = ?, retired_date = ?, updated_at = ?, version = ? '
        'WHERE id = ?',
        [_ownerId, retiredAt.millisecondsSinceEpoch, now, newVersion, id],
      );
    });
  }

  /// Deletes the cell only if no dives can be attributed to its
  /// `[installedDate, retiredDate)` window. Returns true on delete.
  Future<bool> deleteCellIfUnused(String id) async {
    final cell = await getCell(id);
    if (cell == null) return false;

    final installed = cell.installedDate;
    final retired = cell.retiredDate;

    if (installed == null && retired == null) {
      await _ps.execute('DELETE FROM oxygen_cells WHERE id = ?', [id]);
      return true;
    }

    final query = _drift.select(_drift.dives);
    if (installed != null) {
      query.where((t) => t.startTime.isBiggerOrEqualValue(installed ~/ 1000));
    }
    if (retired != null) {
      query.where((t) => t.startTime.isSmallerThanValue(retired ~/ 1000));
    }
    query.limit(1);
    final overlapping = await query.get();
    if (overlapping.isNotEmpty) return false;

    await _ps.execute('DELETE FROM oxygen_cells WHERE id = ?', [id]);
    return true;
  }

  // ── Cell aggregation ─────────────────────────────────────────────────────

  /// Per-dive surface-mV time series for a cell. Surface mV = mean of
  /// `cellMv[slot]` over samples with `depthM < 1.0` AND `cellMv >= 5.0`.
  Future<List<({DateTime date, double mv, String diveId})>>
      surfaceMvSeriesForCell(String cellId) async {
    final cell = await getCell(cellId);
    if (cell == null) return const [];
    final mvCol = cell.slot - 1;
    if (mvCol < 0 || mvCol > 2) return const [];

    final dives = await _divesInWindow(cell.installedDate, cell.retiredDate);
    if (dives.isEmpty) return const [];
    final samplesById = await _samplesForDives(dives);

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
      final dives = await _divesInWindow(cell.installedDate, cell.retiredDate);
      if (dives.isNotEmpty) {
        final samplesById = await _samplesForDives(dives);
        for (final dive in dives) {
          final sample = samplesById[dive.id];
          if (sample == null) continue;
          final peak = _peakMvForSlot(sample, mvCol);
          if (peak == null) continue;
          divePeaks.add((
            start: DateTime.fromMillisecondsSinceEpoch(dive.startTime * 1000),
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

  Future<List<Dive>> _divesInWindow(int? installedMs, int? retiredMs) {
    final query = _drift.select(_drift.dives);
    if (installedMs != null) {
      query.where((t) => t.startTime.isBiggerOrEqualValue(installedMs ~/ 1000));
    }
    if (retiredMs != null) {
      query.where((t) => t.startTime.isSmallerThanValue(retiredMs ~/ 1000));
    }
    query.orderBy([(t) => OrderingTerm.asc(t.startTime)]);
    return query.get();
  }

  Future<Map<String, DiveSample>> _samplesForDives(List<Dive> dives) async {
    final ids = dives.map((d) => d.id).toList();
    if (ids.isEmpty) return const {};
    final samples = await (_drift.select(_drift.diveSamples)
          ..where((t) => t.diveId.isIn(ids)))
        .get();
    return {for (final s in samples) s.diveId: s};
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
    // Microsecond suffix avoids id collisions when two sessions are
    // created in the same millisecond (PowerSync enforces UNIQUE on id).
    final id = 'scrub_${DateTime.now().microsecondsSinceEpoch}';
    await _ps.execute(
      'INSERT INTO scrubber_sessions '
      '(id, owner_id, started_date, total_minutes, media_type, notes, '
      'created_at, updated_at, deleted_at, version, sync_status) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [id, _ownerId, startedDate.millisecondsSinceEpoch, null,
        mediaType, notes, now, now, null, 1, 0],
    );
    return id;
  }

  Future<List<ScrubberSession>> listScrubberSessions() async {
    final rows = await _ps.getAll(
      'SELECT * FROM scrubber_sessions WHERE deleted_at IS NULL',
    );
    final sessions = rows.map(_rowToScrubberSession).toList();
    // Active (totalMinutes IS NULL) first; closed sorted by startedDate desc.
    sessions.sort((a, b) {
      if (a.totalMinutes == null && b.totalMinutes != null) return -1;
      if (a.totalMinutes != null && b.totalMinutes == null) return 1;
      return (b.startedDate ?? 0).compareTo(a.startedDate ?? 0);
    });
    return sessions;
  }

  Future<ScrubberSession?> getScrubberSession(String id) async {
    final row = await _ps.getOptional(
      'SELECT * FROM scrubber_sessions WHERE id = ?',
      [id],
    );
    return row == null ? null : _rowToScrubberSession(row);
  }

  Future<void> updateScrubberSession(
    String id, {
    DateTime? startedDate,
    String? mediaType,
    String? notes,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _ps.writeTransaction((tx) async {
      final existing = await tx.getOptional(
        'SELECT * FROM scrubber_sessions WHERE id = ?',
        [id],
      );
      if (existing == null) return;
      final newVersion = (existing['version'] as int? ?? 0) + 1;
      final newStarted = startedDate?.millisecondsSinceEpoch
          ?? existing['started_date'] as int?;
      final newMediaType = mediaType ?? existing['media_type'] as String?;
      final newNotes = notes ?? existing['notes'] as String?;
      await tx.execute(
        'UPDATE scrubber_sessions SET '
        'owner_id = ?, started_date = ?, media_type = ?, notes = ?, '
        'updated_at = ?, version = ? '
        'WHERE id = ?',
        [_ownerId, newStarted, newMediaType, newNotes, now, newVersion, id],
      );
    });
  }

  Future<void> closeScrubberSession(String id, {required DateTime endedAt}) async {
    final session = await getScrubberSession(id);
    if (session == null) return;
    final minutes = await accumulatedMinutesForSession(
      id,
      endBoundOverride: endedAt,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    await _ps.writeTransaction((tx) async {
      final existing = await tx.getOptional(
        'SELECT version FROM scrubber_sessions WHERE id = ?',
        [id],
      );
      if (existing == null) return;
      final newVersion = (existing['version'] as int? ?? 0) + 1;
      await tx.execute(
        'UPDATE scrubber_sessions SET '
        'owner_id = ?, total_minutes = ?, updated_at = ?, version = ? '
        'WHERE id = ?',
        [_ownerId, minutes, now, newVersion, id],
      );
    });
  }

  Future<void> deleteScrubberSession(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _ps.writeTransaction((tx) async {
      final existing = await tx.getOptional(
        'SELECT version FROM scrubber_sessions WHERE id = ?',
        [id],
      );
      if (existing == null) return;
      final newVersion = (existing['version'] as int? ?? 0) + 1;
      await tx.execute(
        'UPDATE scrubber_sessions SET '
        'owner_id = ?, deleted_at = ?, updated_at = ?, version = ? '
        'WHERE id = ?',
        [_ownerId, now, now, newVersion, id],
      );
    });
  }

  /// Forward-compatible hook called per imported dive. No-op when
  /// [scrubberResetAt] is null.
  Future<void> applyScrubberEvents({
    required DateTime? scrubberResetAt,
    required int dcSerial,
  }) async {
    if (scrubberResetAt == null) return;
    final open = await _ps.getAll(
      'SELECT id FROM scrubber_sessions '
      'WHERE deleted_at IS NULL AND total_minutes IS NULL',
    );
    for (final s in open) {
      await closeScrubberSession(s['id'] as String, endedAt: scrubberResetAt);
    }
    await addScrubberSession(startedDate: scrubberResetAt);
    // dcSerial reserved for a future migration that ties scrubber sessions
    // to a specific dive computer (multi-rig support).
    // ignore: unused_local_variable
    final _ = dcSerial;
  }

  /// Sum of dive runtimes (in minutes) whose `startTime` falls in
  /// [session.startedDate, endBound). Endbound = next session's startedDate
  /// or [endBoundOverride] when closing.
  Future<int> accumulatedMinutesForSession(
    String id, {
    DateTime? endBoundOverride,
  }) async {
    final session = await getScrubberSession(id);
    if (session == null || session.startedDate == null) return 0;

    int? endEpoch = endBoundOverride?.millisecondsSinceEpoch;
    if (endEpoch == null) {
      final later = await _ps.getAll(
        'SELECT started_date FROM scrubber_sessions '
        'WHERE deleted_at IS NULL AND started_date > ?',
        [session.startedDate],
      );
      if (later.isNotEmpty) {
        endEpoch = later
            .map((s) => s['started_date'] as int)
            .reduce((a, b) => a < b ? a : b);
      }
    }

    final query = _drift.select(_drift.dives)
      ..where((t) => t.startTime.isBiggerOrEqualValue(session.startedDate! ~/ 1000));
    if (endEpoch != null) {
      query.where((t) => t.startTime.isSmallerThanValue(endEpoch! ~/ 1000));
    }
    final dives = await query.get();

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
    await _ps.execute(
      'INSERT INTO cylinders '
      '(id, owner_id, label, role, bailout_order, volume_liters, '
      'working_pressure_bar, gas_mix, notes, '
      'created_at, updated_at, deleted_at, version, sync_status) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [id, _ownerId, label, role, effectiveOrder, volumeLiters,
        workingPressureBar, gasMix, notes, now, now, null, 1, 0],
    );
    return id;
  }

  Future<List<Cylinder>> listCylinders() async {
    final rows = await _ps.getAll(
      'SELECT * FROM cylinders WHERE deleted_at IS NULL',
    );
    final cyls = rows.map(_rowToCylinder).toList();
    const roleOrder = {
      CylinderRole.oxygen: 0,
      CylinderRole.diluent: 1,
      CylinderRole.bailout: 2,
      CylinderRole.offboard: 3,
    };
    cyls.sort((a, b) {
      final ra = roleOrder[a.role] ?? 99;
      final rb = roleOrder[b.role] ?? 99;
      if (ra != rb) return ra.compareTo(rb);
      final oa = a.bailoutOrder ?? 0;
      final ob = b.bailoutOrder ?? 0;
      if (oa != ob) return oa.compareTo(ob);
      return a.label.compareTo(b.label);
    });
    return cyls;
  }

  Future<Cylinder?> getCylinder(String id) async {
    final row = await _ps.getOptional(
      'SELECT * FROM cylinders WHERE id = ?',
      [id],
    );
    return row == null ? null : _rowToCylinder(row);
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
    await _ps.writeTransaction((tx) async {
      final existing = await tx.getOptional(
        'SELECT * FROM cylinders WHERE id = ?',
        [id],
      );
      if (existing == null) return;
      final newVersion = (existing['version'] as int? ?? 0) + 1;
      final newRole = role ?? existing['role'] as String;
      final newLabel = label ?? existing['label'] as String;
      final int? newBailoutOrder;
      if (newRole != CylinderRole.bailout) {
        newBailoutOrder = null;
      } else if (bailoutOrder != null) {
        newBailoutOrder = bailoutOrder;
      } else {
        newBailoutOrder = existing['bailout_order'] as int?;
      }
      final newVolume = volumeLiters ?? (existing['volume_liters'] as num).toDouble();
      final newPressure = workingPressureBar ?? existing['working_pressure_bar'] as int;
      final newGas = gasMix ?? existing['gas_mix'] as String?;
      final newNotes = notes ?? existing['notes'] as String?;
      await tx.execute(
        'UPDATE cylinders SET '
        'owner_id = ?, label = ?, role = ?, bailout_order = ?, '
        'volume_liters = ?, working_pressure_bar = ?, gas_mix = ?, notes = ?, '
        'updated_at = ?, version = ? '
        'WHERE id = ?',
        [_ownerId, newLabel, newRole, newBailoutOrder, newVolume,
          newPressure, newGas, newNotes, now, newVersion, id],
      );
    });
  }

  Future<void> softDeleteCylinder(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _ps.writeTransaction((tx) async {
      final existing = await tx.getOptional(
        'SELECT version FROM cylinders WHERE id = ?',
        [id],
      );
      if (existing == null) return;
      final newVersion = (existing['version'] as int? ?? 0) + 1;
      await tx.execute(
        'UPDATE cylinders SET '
        'owner_id = ?, deleted_at = ?, updated_at = ?, version = ? '
        'WHERE id = ?',
        [_ownerId, now, now, newVersion, id],
      );
    });
  }

  // ── PressureMappings ─────────────────────────────────────────────────────
  //
  // Composite Drift PK (dive_computer_id, channel_index); synthesized cloud
  // id is "<dive_computer_id>:<channel_index>".

  Future<List<PressureMapping>> listPressureMappings(
      String diveComputerId) async {
    final rows = await _ps.getAll(
      'SELECT * FROM pressure_mappings '
      'WHERE dive_computer_id = ? AND deleted_at IS NULL '
      'ORDER BY channel_index ASC',
      [diveComputerId],
    );
    return rows.map(_rowToPressureMapping).toList();
  }

  Future<void> setPressureMapping({
    required String diveComputerId,
    required int channelIndex,
    required String? cylinderId,
  }) async {
    final id = '$diveComputerId:$channelIndex';
    final now = DateTime.now().millisecondsSinceEpoch;
    await _ps.writeTransaction((tx) async {
      final existing = await tx.getOptional(
        'SELECT version FROM pressure_mappings WHERE id = ?',
        [id],
      );
      if (existing == null) {
        await tx.execute(
          'INSERT INTO pressure_mappings '
          '(id, owner_id, dive_computer_id, channel_index, cylinder_id, '
          'created_at, updated_at, deleted_at, version, sync_status) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [id, _ownerId, diveComputerId, channelIndex, cylinderId,
            now, now, null, 1, 0],
        );
      } else {
        final newVersion = (existing['version'] as int? ?? 0) + 1;
        await tx.execute(
          'UPDATE pressure_mappings SET '
          'owner_id = ?, cylinder_id = ?, updated_at = ?, version = ? '
          'WHERE id = ?',
          [_ownerId, cylinderId, now, newVersion, id],
        );
      }
    });
  }

  /// Best-effort enumeration of pressure-channel indexes the device has
  /// logged. MVP returns channels that already have a mapping.
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

  // ── Mapping helpers ─────────────────────────────────────────────────────

  DiveCylinder _rowToDiveCylinder(Map<String, dynamic> r) => DiveCylinder(
        diveId: r['dive_id'] as String,
        gasMixIndex: r['gas_mix_index'] as int,
        cylinderId: r['cylinder_id'] as String?,
        createdAt: r['created_at'] as int,
        updatedAt: r['updated_at'] as int,
        deletedAt: r['deleted_at'] as int?,
        version: r['version'] as int? ?? 1,
        syncStatus: r['sync_status'] as int? ?? 0,
        ownerId: r['owner_id'] as String?,
      );

  DiveComputer _rowToDiveComputer(Map<String, dynamic> r) => DiveComputer(
        id: r['id'] as String,
        serial: r['serial'] as int,
        model: r['model'] as int,
        firmwareVersion: r['firmware_version'] as int?,
        nickname: r['nickname'] as String?,
        createdAt: r['created_at'] as int,
        updatedAt: r['updated_at'] as int,
        deletedAt: r['deleted_at'] as int?,
        version: r['version'] as int? ?? 1,
        syncStatus: r['sync_status'] as int? ?? 0,
        ownerId: r['owner_id'] as String?,
      );

  OxygenCell _rowToOxygenCell(Map<String, dynamic> r) => OxygenCell(
        id: r['id'] as String,
        slot: r['slot'] as int,
        label: r['label'] as String?,
        installedDate: r['installed_date'] as int?,
        retiredDate: r['retired_date'] as int?,
        notes: r['notes'] as String?,
        createdAt: r['created_at'] as int,
        updatedAt: r['updated_at'] as int,
        deletedAt: r['deleted_at'] as int?,
        version: r['version'] as int? ?? 1,
        syncStatus: r['sync_status'] as int? ?? 0,
        ownerId: r['owner_id'] as String?,
      );

  ScrubberSession _rowToScrubberSession(Map<String, dynamic> r) =>
      ScrubberSession(
        id: r['id'] as String,
        startedDate: r['started_date'] as int?,
        totalMinutes: r['total_minutes'] as int?,
        mediaType: r['media_type'] as String?,
        notes: r['notes'] as String?,
        createdAt: r['created_at'] as int,
        updatedAt: r['updated_at'] as int,
        deletedAt: r['deleted_at'] as int?,
        version: r['version'] as int? ?? 1,
        syncStatus: r['sync_status'] as int? ?? 0,
        ownerId: r['owner_id'] as String?,
      );

  Cylinder _rowToCylinder(Map<String, dynamic> r) => Cylinder(
        id: r['id'] as String,
        label: r['label'] as String,
        role: r['role'] as String,
        bailoutOrder: r['bailout_order'] as int?,
        volumeLiters: (r['volume_liters'] as num).toDouble(),
        workingPressureBar: r['working_pressure_bar'] as int,
        gasMix: r['gas_mix'] as String?,
        notes: r['notes'] as String?,
        createdAt: r['created_at'] as int,
        updatedAt: r['updated_at'] as int,
        deletedAt: r['deleted_at'] as int?,
        version: r['version'] as int? ?? 1,
        syncStatus: r['sync_status'] as int? ?? 0,
        ownerId: r['owner_id'] as String?,
      );

  PressureMapping _rowToPressureMapping(Map<String, dynamic> r) =>
      PressureMapping(
        diveComputerId: r['dive_computer_id'] as String,
        channelIndex: r['channel_index'] as int,
        cylinderId: r['cylinder_id'] as String?,
        createdAt: r['created_at'] as int,
        updatedAt: r['updated_at'] as int,
        deletedAt: r['deleted_at'] as int?,
        version: r['version'] as int? ?? 1,
        syncStatus: r['sync_status'] as int? ?? 0,
        ownerId: r['owner_id'] as String?,
      );
}
