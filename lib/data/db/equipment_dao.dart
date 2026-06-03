/// Data Access Object for equipment-view tables: dive computers, oxygen
/// cells, scrubber sessions, cylinders, pressure-channel mappings, and
/// per-dive cylinder assignments.
///
/// Phase 2.3: hybrid backend. The six sync-eligible tables live in
/// PowerSync (raw SQL via the `PowerSyncDatabase` view). Analysis
/// methods that join with imported dive data still query Drift directly
/// — `recentImportsForComputer`, `mvSeriesForCell`, scrubber
/// minute accumulation. The DAO holds both database handles and stitches
/// the two halves in Dart.
///
/// Drift row types (`Cylinder`, `OxygenCell`, etc.) are kept as the
/// public API surface so the existing UI/notifier callers don't change;
/// internally they're rebuilt from PowerSync `Map<String, dynamic>` rows.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../../analysis/cell_health.dart';
import '../../sync/cloud/ccrlogger_backend_connector.dart' show SessionSource;
import '../models/equipment.dart' show CylinderRole, SlotInUseException;
import '../sample_codec/column_packer.dart';
import 'database.dart';

/// One per-dive mV reading for a cell: the dive's start, the mV value, and
/// the dive id (for tap-through to the dive).
typedef MvPoint = ({DateTime date, double mv, String diveId});

class EquipmentDao {
  final AppDatabase _drift;
  final PowerSyncDatabase _ps;
  final SessionSource _session;

  EquipmentDao(this._drift, this._ps, this._session);

  String? get _ownerId => _session.currentSession?.user.id;

  // ── Watch streams ───────────────────────────────────────────────────────
  //
  // Each fires on every change to its table — including remote writes that
  // PowerSync pulls from the cloud. Emits an initial event on subscription.
  // Notifiers wire these into `load()` so screens stay in sync without a
  // pull-to-refresh.

  Stream<void> watchCylinders() =>
      _ps.watch('SELECT 1 FROM cylinders LIMIT 1').map((_) {});

  Stream<void> watchOxygenCells() =>
      _ps.watch('SELECT 1 FROM oxygen_cells LIMIT 1').map((_) {});

  Stream<void> watchScrubberSessions() =>
      _ps.watch('SELECT 1 FROM scrubber_sessions LIMIT 1').map((_) {});

  Stream<void> watchDiveComputers() =>
      _ps.watch('SELECT 1 FROM dive_computers LIMIT 1').map((_) {});

  Stream<void> watchPressureMappings() =>
      _ps.watch('SELECT 1 FROM pressure_mappings LIMIT 1').map((_) {});

  Stream<void> watchDiveCylinders() =>
      _ps.watch('SELECT 1 FROM dive_cylinders LIMIT 1').map((_) {});

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

    // Dives live in PowerSync (not Drift) — reuse the same window query the
    // cell aggregation uses, so a cell that actually has dives in its window
    // is correctly protected from deletion.
    final overlapping = await _divesInWindow(installed, retired);
    if (overlapping.isNotEmpty) return false;

    await _ps.execute('DELETE FROM oxygen_cells WHERE id = ?', [id]);
    return true;
  }

  // ── Cell aggregation ─────────────────────────────────────────────────────

  /// Per-dive surface-mV AND peak-mV time series for a cell, computed in a
  /// single pass over the cell's dive window so the sample blobs are loaded
  /// once. Surface mV = mean of `cellMv[slot]` over samples with `depthM < 1.0`
  /// AND `cellMv >= 5.0`. Peak mV = max `cellMv[slot]` over samples with
  /// `cellMv >= 5.0`. The two lists may differ in length (a dive can have a
  /// peak reading but no in-record surface samples).
  Future<({List<MvPoint> surface, List<MvPoint> peak})> mvSeriesForCell(
      String cellId) async {
    final empty = (surface: <MvPoint>[], peak: <MvPoint>[]);
    final cell = await getCell(cellId);
    if (cell == null) return empty;
    final mvCol = cell.slot - 1;
    if (mvCol < 0 || mvCol > 2) return empty;

    final dives = await _divesInWindow(cell.installedDate, cell.retiredDate);
    if (dives.isEmpty) return empty;
    final samplesById = await _samplesForDives(dives);

    final surface = <MvPoint>[];
    final peak = <MvPoint>[];
    for (final dive in dives) {
      final sample = samplesById[dive.id];
      if (sample == null) continue;
      final date = DateTime.fromMillisecondsSinceEpoch(dive.startTime * 1000);
      final s = _computeSurfaceMv(sample, mvCol);
      if (s != null) surface.add((date: date, mv: s, diveId: dive.id));
      final p = _peakMvForSlot(sample, mvCol);
      if (p != null) peak.add((date: date, mv: p, diveId: dive.id));
    }
    return (surface: surface, peak: peak);
  }

  /// Surface-mV series only. Thin delegate over [mvSeriesForCell] kept for
  /// existing callers.
  Future<List<MvPoint>> surfaceMvSeriesForCell(String cellId) async =>
      (await mvSeriesForCell(cellId)).surface;

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
      final peakSeries = (await mvSeriesForCell(cellId)).peak;
      for (final p in peakSeries) {
        divePeaks.add((start: p.date, peakMv: p.mv));
      }
    }

    return evaluateCellHealth(
      now: now ?? DateTime.now(),
      installedDate: installedDate,
      divePeaks: divePeaks,
    );
  }

  /// Dives whose start falls in `[installed, retired)`, oldest first.
  /// Reads from PowerSync — dives live there since Phase 2.5, NOT in the Drift
  /// `dives` table (which is empty). Returns only the fields the cell
  /// aggregation needs (id, start_time in epoch seconds).
  Future<List<({String id, int startTime})>> _divesInWindow(
      int? installedMs, int? retiredMs) async {
    final clauses = <String>['deleted_at IS NULL'];
    final args = <Object?>[];
    if (installedMs != null) {
      clauses.add('start_time >= ?');
      args.add(installedMs ~/ 1000);
    }
    if (retiredMs != null) {
      clauses.add('start_time < ?');
      args.add(retiredMs ~/ 1000);
    }
    final rows = await _ps.getAll(
      'SELECT id, start_time FROM dives WHERE ${clauses.join(' AND ')} '
      'ORDER BY start_time ASC',
      args,
    );
    return [
      for (final r in rows)
        (id: r['id'] as String, startTime: r['start_time'] as int)
    ];
  }

  /// Cell-mV + depth sample blobs for the given dives, keyed by dive id.
  /// Reads from PowerSync (`dive_samples`, id = dive id); the blobs are stored
  /// base64-encoded there, so decode them back to bytes for [ColumnPacker].
  Future<Map<String, _CellSampleData>> _samplesForDives(
      List<({String id, int startTime})> dives) async {
    final ids = dives.map((d) => d.id).toList();
    if (ids.isEmpty) return const {};
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await _ps.getAll(
      'SELECT id, sample_count, depth_blob, cell_mv0_blob, cell_mv1_blob, '
      'cell_mv2_blob FROM dive_samples WHERE id IN ($placeholders)',
      ids,
    );
    return {
      for (final r in rows)
        r['id'] as String: _CellSampleData(
          sampleCount: r['sample_count'] as int,
          depthBlob: base64Decode(r['depth_blob'] as String),
          cellMv0Blob: base64Decode(r['cell_mv0_blob'] as String),
          cellMv1Blob: base64Decode(r['cell_mv1_blob'] as String),
          cellMv2Blob: base64Decode(r['cell_mv2_blob'] as String),
        ),
    };
  }

  double? _peakMvForSlot(_CellSampleData sample, int mvCol) {
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

  double? _computeSurfaceMv(_CellSampleData sample, int mvCol) {
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
      'working_pressure_bar, notes, '
      'created_at, updated_at, deleted_at, version, sync_status) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [id, _ownerId, label, role, effectiveOrder, volumeLiters,
        workingPressureBar, notes, now, now, null, 1, 0],
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
      final newNotes = notes ?? existing['notes'] as String?;
      await tx.execute(
        'UPDATE cylinders SET '
        'owner_id = ?, label = ?, role = ?, bailout_order = ?, '
        'volume_liters = ?, working_pressure_bar = ?, notes = ?, '
        'updated_at = ?, version = ? '
        'WHERE id = ?',
        [_ownerId, newLabel, newRole, newBailoutOrder, newVolume,
          newPressure, newNotes, now, newVersion, id],
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

  // ── DiveBailoutCarry ────────────────────────────────────────────────────
  //
  // Per-dive list of OC bailout cylinders the diver carried. Each row pairs a
  // physical [Cylinder] with the gas it held on this dive and a fill pressure;
  // null fill means "assume the cylinder's working pressure (full)". The
  // bailout planner reads these rows for the active dive — empty list → fall
  // through to standard Scenario B.

  // Two screens subscribe to bailout-carry changes simultaneously when
  // the dive-detail TabBarView keeps Details + Equipment tabs alive at
  // once. PowerSync's underlying `_ps.watch(sql)` returns a single-
  // subscription stream, so we cache + broadcast once per DAO instance
  // — multiple listeners now coexist without "Bad state: Stream has
  // already been listened to".
  Stream<void>? _diveBailoutCarryWatchStream;
  Stream<void> watchDiveBailoutCarry() => _diveBailoutCarryWatchStream ??= _ps
      .watch('SELECT 1 FROM dive_bailout_carry LIMIT 1')
      .map((_) {})
      .asBroadcastStream();

  Future<List<DiveBailoutCarryData>> listBailoutCarry(String diveId) async {
    final rows = await _ps.getAll(
      'SELECT * FROM dive_bailout_carry '
      'WHERE dive_id = ? AND deleted_at IS NULL '
      'ORDER BY bailout_order ASC',
      [diveId],
    );
    return rows.map(_rowToBailoutCarry).toList();
  }

  Future<List<({DiveBailoutCarryData carry, Cylinder cylinder})>>
      listBailoutCarryWithCylinders(String diveId) async {
    final rows = await _ps.getAll(
      // Alias every dive_bailout_carry column with a `bc_` prefix.
      // Otherwise `c.*` brings in cylinders.bailout_order (NULL for
      // non-bailout-role cylinders), cylinders.gas_mix, and
      // cylinders.dive_id — these silently overwrite the bc.* values
      // in the result map because SQLite uses the LAST-seen name
      // when columns collide. Result was a `Null is not a subtype of
      // int` cast failure on the bailoutOrder field.
      'SELECT bc.id AS bc_id, bc.dive_id AS bc_dive_id, '
      '       bc.cylinder_id AS bc_cylinder_id, bc.gas_mix AS bc_gas_mix, '
      '       bc.fill_pressure_bar AS bc_fill_pressure_bar, '
      '       bc.bailout_order AS bc_bailout_order, '
      '       bc.created_at AS bc_created_at, bc.updated_at AS bc_updated_at, '
      '       bc.deleted_at AS bc_deleted_at, bc.version AS bc_version, '
      '       bc.sync_status AS bc_sync_status, bc.owner_id AS bc_owner_id, '
      '       c.* '
      'FROM dive_bailout_carry bc '
      'JOIN cylinders c ON c.id = bc.cylinder_id '
      'WHERE bc.dive_id = ? AND bc.deleted_at IS NULL '
      'ORDER BY bc.bailout_order ASC',
      [diveId],
    );
    return rows.map((r) {
      final carry = DiveBailoutCarryData(
        id: r['bc_id'] as String,
        diveId: r['bc_dive_id'] as String,
        cylinderId: r['bc_cylinder_id'] as String,
        gasMix: r['bc_gas_mix'] as String,
        fillPressureBar: r['bc_fill_pressure_bar'] as int?,
        bailoutOrder: r['bc_bailout_order'] as int,
        createdAt: r['bc_created_at'] as int,
        updatedAt: r['bc_updated_at'] as int,
        deletedAt: r['bc_deleted_at'] as int?,
        version: r['bc_version'] as int? ?? 1,
        syncStatus: r['bc_sync_status'] as int? ?? 0,
        ownerId: r['bc_owner_id'] as String?,
      );
      return (carry: carry, cylinder: _rowToCylinder(r));
    }).toList();
  }

  Future<String> addBailoutCarry({
    required String diveId,
    required String cylinderId,
    required String gasMix,
    int? fillPressureBar,
    required int bailoutOrder,
  }) async {
    // id is the deterministic `(diveId, cylinderId)` composite —
    // [deleteBailoutCarry] is a soft-delete that leaves the row in
    // place with `deleted_at` set, so a plain INSERT here would fail
    // with a UNIQUE-constraint error on any "add → delete → re-add"
    // cycle.
    //
    // PowerSync exposes its tables as views, which can't be UPSERTed
    // (SQLite rejects ON CONFLICT on a view), so do a SELECT-first
    // and dispatch to UPDATE (revive a soft-deleted row) or INSERT
    // (the common path) explicitly.
    final id = '$diveId:$cylinderId';
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await _ps.getOptional(
      'SELECT id FROM dive_bailout_carry WHERE id = ?',
      [id],
    );
    if (existing != null) {
      await _ps.execute(
        'UPDATE dive_bailout_carry SET '
        '  gas_mix = ?, '
        '  fill_pressure_bar = ?, '
        '  bailout_order = ?, '
        '  deleted_at = NULL, '
        '  updated_at = ?, '
        '  version = COALESCE(version, 0) + 1, '
        '  sync_status = 0 '
        'WHERE id = ?',
        [gasMix, fillPressureBar, bailoutOrder, now, id],
      );
    } else {
      await _ps.execute(
        'INSERT INTO dive_bailout_carry '
        '(id, owner_id, dive_id, cylinder_id, gas_mix, fill_pressure_bar, '
        ' bailout_order, created_at, updated_at, deleted_at, version, '
        ' sync_status) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, 1, 0)',
        [id, _ownerId, diveId, cylinderId, gasMix, fillPressureBar,
          bailoutOrder, now, now],
      );
    }
    return id;
  }

  Future<void> updateBailoutCarry(
    String id, {
    String? gasMix,
    int? fillPressureBar,
    int? bailoutOrder,
  }) async {
    final sets = <String>[];
    final args = <Object?>[];
    if (gasMix != null) {
      sets.add('gas_mix = ?');
      args.add(gasMix);
    }
    if (fillPressureBar != null) {
      sets.add('fill_pressure_bar = ?');
      args.add(fillPressureBar);
    }
    if (bailoutOrder != null) {
      sets.add('bailout_order = ?');
      args.add(bailoutOrder);
    }
    if (sets.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    sets.add('updated_at = ?');
    args.add(now);
    args.add(id);
    await _ps.execute(
      'UPDATE dive_bailout_carry SET ${sets.join(", ")} WHERE id = ?',
      args,
    );
  }

  Future<void> deleteBailoutCarry(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _ps.execute(
      'UPDATE dive_bailout_carry '
      'SET deleted_at = ?, updated_at = ? WHERE id = ?',
      [now, now, id],
    );
  }

  /// One-shot local GC: hard-deletes `dive_bailout_carry` rows whose `dive_id`
  /// matches no row in `dives` at all — true orphans left behind when a dive
  /// vanished entirely (re-import re-hash, "Reset Everything", or a delete from
  /// before [DiveDao.softDeleteDive]'s cascade landed). Left in place they ride
  /// the upload queue as an unresolvable FK 23503 and wedge sync; the connector
  /// now drops the op, and this clears the dead local row so it can't reappear.
  ///
  /// A *soft-deleted* dive still HAS its `dives` row, so its bailout rows are
  /// NOT orphans here — they're handled by the delete cascade. The view delete
  /// propagates a DELETE op, which is harmless/desirable: any cloud row is
  /// equally orphaned. Returns the number of rows removed.
  ///
  /// Run once at startup before sync connects, on the last persisted (and thus
  /// referentially consistent — dives + dive_bailout_carry share one sync
  /// bucket) checkpoint, so it can't race an in-flight download.
  Future<int> purgeOrphanedBailoutCarry() async {
    const where = 'WHERE NOT EXISTS '
        '(SELECT 1 FROM dives WHERE dives.id = dive_bailout_carry.dive_id)';
    final orphans =
        await _ps.getAll('SELECT id FROM dive_bailout_carry $where');
    if (orphans.isEmpty) return 0;
    await _ps.execute('DELETE FROM dive_bailout_carry $where');
    return orphans.length;
  }

  DiveBailoutCarryData _rowToBailoutCarry(Map<String, dynamic> r) =>
      DiveBailoutCarryData(
        id: r['id'] as String,
        diveId: r['dive_id'] as String,
        cylinderId: r['cylinder_id'] as String,
        gasMix: r['gas_mix'] as String,
        fillPressureBar: r['fill_pressure_bar'] as int?,
        bailoutOrder: r['bailout_order'] as int,
        createdAt: r['created_at'] as int,
        updatedAt: r['updated_at'] as int,
        deletedAt: r['deleted_at'] as int?,
        version: r['version'] as int? ?? 1,
        syncStatus: r['sync_status'] as int? ?? 0,
        ownerId: r['owner_id'] as String?,
      );

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

/// Decoded cell-mV + depth sample blobs for one dive, sourced from PowerSync's
/// `dive_samples` row (base64 decoded). Just the columns the cell-health
/// aggregation reads — not the full [DiveSample].
class _CellSampleData {
  final int sampleCount;
  final Uint8List depthBlob;
  final Uint8List cellMv0Blob;
  final Uint8List cellMv1Blob;
  final Uint8List cellMv2Blob;
  const _CellSampleData({
    required this.sampleCount,
    required this.depthBlob,
    required this.cellMv0Blob,
    required this.cellMv1Blob,
    required this.cellMv2Blob,
  });
}
