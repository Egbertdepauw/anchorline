/// Data Access Object for dive CRUD operations.
///
/// Phase 2.5 hybrid: dive metadata + parsed samples live in PowerSync
/// so they sync across devices ("import once on iPhone, see everywhere").
/// The raw Shearwater binary blob stays local in Drift's `dive_raw_blobs`
/// table — it's only needed for re-parsing after a parser bug fix and
/// not worth syncing.
///
/// Sample blobs are gzipped Float32 columnar binary in transit through
/// the codec; PowerSync's only column types are text/integer/real, so we
/// base64-encode them at write and decode at read. Mirrors how
/// `dive_annotations` handles jsonb at the seam.
///
/// Returned `Dive` instances always carry an empty `rawBlob` field —
/// the legacy column on the Drift `Dive` row class is unused now;
/// callers that need raw bytes call `getRawBlob(id)` which goes to
/// `dive_raw_blobs`.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../models/sample_set.dart';
import '../sample_codec/sample_codec.dart';
import '../../shearwater/parser/dive_converter.dart';
import '../../sync/cloud/ccrlogger_backend_connector.dart' show SessionSource;
import 'database.dart';

class DiveDao {
  final AppDatabase _drift;
  final PowerSyncDatabase _ps;
  final SessionSource _session;

  DiveDao(this._drift, this._ps, this._session);

  String? get _ownerId => _session.currentSession?.user.id;

  // ── Watch streams ───────────────────────────────────────────────────────

  /// Fires whenever any row in `dives` changes (local writes or
  /// PowerSync-driven updates from the cloud). Emits an initial event on
  /// subscription.
  Stream<void> watchChanges() =>
      _ps.watch('SELECT 1 FROM dives LIMIT 1').map((_) {});

  // ── Import ─────────────────────────────────────────────────────────────

  /// Atomically import a dive: PowerSync `dives` + `dive_samples` +
  /// Drift `dive_raw_blobs`. Returns `true` if newly imported, `false`
  /// if the dive id already existed (dedup happens against PowerSync, so
  /// a dive imported on another device + synced down also counts as a
  /// duplicate — exactly what we want for "import once").
  Future<bool> importDive({
    required ConvertedDive converted,
    required Uint8List rawBlob,
    required int parserVersion,
  }) async {
    final dive = converted.dive;

    if (await diveExists(dive.id)) {
      // Even when metadata already synced from another device, store the
      // raw blob locally — the parser-bug-fix re-parse path needs it.
      await _drift.into(_drift.diveRawBlobs).insertOnConflictUpdate(
            DiveRawBlobsCompanion.insert(diveId: dive.id, rawBlob: rawBlob),
          );
      return false;
    }

    final sampleBlobs = SampleCodec.encode(converted.samples);
    final gasMixesJson =
        jsonEncode(dive.gasMixes.map((g) => g.toJson()).toList());
    final tanksJson = dive.tanks.isEmpty
        ? null
        : jsonEncode(dive.tanks.map((t) => t.toJson()).toList());
    // Per-cell calibration factors. Empty list (OC dives) → null so the
    // mapper / chart fallback (0.021) is used uniformly with legacy rows.
    final sensorCalibrationJson = dive.sensorCalibration.isEmpty
        ? null
        : jsonEncode(dive.sensorCalibration);

    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    await _ps.writeTransaction((tx) async {
      await tx.execute(
        'INSERT INTO dives '
        '(id, owner_id, dc_serial, dc_dive_number, start_time, end_time, '
        'utc_offset_minutes, duration_seconds, max_depth_mm, dive_mode, '
        'deco_model, gf_low, gf_high, atmospheric_pressure_mbar, '
        'water_density, log_version, dc_model, dc_firmware, '
        'sample_interval_ms, gas_mixes_json, tanks_json, '
        'sensor_calibration_json, '
        'configured_stack_seconds, stack_remaining_at_start_seconds, '
        'stack_remaining_at_end_seconds, parser_version, imported_at, '
        'subsurface_uploaded_at, deleted_at, version, sync_status) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '
        '?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          dive.id,
          _ownerId,
          dive.dcSerial,
          dive.dcDiveNumber,
          dive.startTime.millisecondsSinceEpoch ~/ 1000,
          dive.endTime.millisecondsSinceEpoch ~/ 1000,
          dive.utcOffsetMinutes,
          dive.duration.inSeconds,
          (dive.maxDepthMeters * 1000).round(),
          dive.diveMode.value,
          dive.decoModel.value,
          dive.gfLow,
          dive.gfHigh,
          dive.atmosphericPressureMbar,
          dive.waterDensityKgM3,
          dive.logVersion,
          dive.dcModel.index,
          null, // dc_firmware (not yet captured by the converter)
          dive.sampleIntervalMs,
          gasMixesJson,
          tanksJson,
          sensorCalibrationJson,
          dive.configuredStackSeconds,
          dive.stackRemainingAtStartSeconds,
          dive.stackRemainingAtEndSeconds,
          parserVersion,
          nowSeconds,
          null, // subsurface_uploaded_at
          null, // deleted_at
          1,
          0,
        ],
      );
      await tx.execute(
        'INSERT INTO dive_samples '
        '(id, owner_id, sample_count, depth_blob, temperature_blob, '
        'ppo2_blob, cell_mv0_blob, cell_mv1_blob, cell_mv2_blob, '
        'setpoint_blob, cns_blob, deco_depth_blob, deco_time_blob, tts_blob, '
        'gas_mix_idx_blob, status_blob, tank_pressures_blob, '
        'created_at, updated_at, version, sync_status) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          dive.id, // PowerSync's implicit `id` PK doubles as dive_id here.
          _ownerId,
          converted.samples.sampleCount,
          base64Encode(sampleBlobs['depth']!),
          base64Encode(sampleBlobs['temperature']!),
          base64Encode(sampleBlobs['ppo2']!),
          base64Encode(sampleBlobs['cellMv0']!),
          base64Encode(sampleBlobs['cellMv1']!),
          base64Encode(sampleBlobs['cellMv2']!),
          base64Encode(sampleBlobs['setpoint']!),
          base64Encode(sampleBlobs['cns']!),
          base64Encode(sampleBlobs['decoDepth']!),
          base64Encode(sampleBlobs['decoTime']!),
          base64Encode(sampleBlobs['tts']!),
          base64Encode(sampleBlobs['gasMixIdx']!),
          base64Encode(sampleBlobs['status']!),
          sampleBlobs['tankPressures'] == null
              ? null
              : base64Encode(sampleBlobs['tankPressures']!),
          nowMs,
          nowMs,
          1,
          0,
        ],
      );
    });

    await _drift.into(_drift.diveRawBlobs).insertOnConflictUpdate(
          DiveRawBlobsCompanion.insert(diveId: dive.id, rawBlob: rawBlob),
        );

    return true;
  }

  // ── Queries ────────────────────────────────────────────────────────────

  /// Check if a dive exists by ID. Includes soft-deleted rows so that
  /// re-importing a soft-deleted dive is still treated as a duplicate
  /// (avoids accidental resurrection via the DC).
  Future<bool> diveExists(String diveId) async {
    final row = await _ps.getOptional(
      'SELECT id FROM dives WHERE id = ?',
      [diveId],
    );
    return row != null;
  }

  /// Returns the subset of [ids] that already exist in the local PowerSync
  /// store. Used by the import flow to hide already-imported dives from the
  /// manifest checklist in one query instead of N round-trips.
  Future<Set<String>> existingDiveIdsAmong(List<String> ids) async {
    if (ids.isEmpty) return const <String>{};
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await _ps.getAll(
      'SELECT id FROM dives WHERE id IN ($placeholders)',
      ids,
    );
    return rows.map((r) => r['id'] as String).toSet();
  }

  /// Get all live dives ordered by start time descending (most recent
  /// first). Excludes soft-deleted rows.
  Future<List<Dive>> getAllDives() async {
    final rows = await _ps.getAll(
      'SELECT * FROM dives WHERE deleted_at IS NULL '
      'ORDER BY start_time DESC',
    );
    return rows.map(_rowToDive).toList();
  }

  /// Get a single dive by ID, or `null` if not found. Returns soft-deleted
  /// rows too — the undo path needs them.
  Future<Dive?> getDive(String id) async {
    final row = await _ps.getOptional('SELECT * FROM dives WHERE id = ?', [id]);
    return row == null ? null : _rowToDive(row);
  }

  /// Soft-deletes a dive. Row stays in PowerSync (so undo works and it
  /// syncs to other devices); list queries filter it out.
  Future<void> softDeleteDive(String id) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _ps.writeTransaction((tx) async {
      final existing = await tx.getOptional(
          'SELECT version FROM dives WHERE id = ?', [id]);
      if (existing == null) return;
      final newVersion = (existing['version'] as int? ?? 0) + 1;
      await tx.execute(
        'UPDATE dives SET owner_id = ?, deleted_at = ?, version = ? WHERE id = ?',
        [_ownerId, nowMs, newVersion, id],
      );
    });
  }

  /// Clears the soft-delete flag — paired with the SnackBar UNDO action.
  Future<void> restoreDive(String id) async {
    await _ps.writeTransaction((tx) async {
      final existing = await tx.getOptional(
          'SELECT version FROM dives WHERE id = ?', [id]);
      if (existing == null) return;
      final newVersion = (existing['version'] as int? ?? 0) + 1;
      await tx.execute(
        'UPDATE dives SET owner_id = ?, deleted_at = NULL, version = ? WHERE id = ?',
        [_ownerId, newVersion, id],
      );
    });
  }

  /// Get the sample data for a dive. Returns `null` if the dive or its
  /// samples don't exist locally yet (e.g. another device imported it
  /// and PowerSync hasn't pulled the samples row yet).
  Future<SampleSet?> getSamples(String diveId) async {
    final samplesRow = await _ps.getOptional(
        'SELECT * FROM dive_samples WHERE id = ?', [diveId]);
    if (samplesRow == null) return null;
    final diveRow = await _ps.getOptional(
        'SELECT sample_interval_ms FROM dives WHERE id = ?', [diveId]);
    final intervalMs = (diveRow?['sample_interval_ms'] as int?) ?? 10000;

    final tankPressuresB64 = samplesRow['tank_pressures_blob'] as String?;

    return SampleCodec.decode(
      blobs: {
        'depth': base64Decode(samplesRow['depth_blob'] as String),
        'temperature': base64Decode(samplesRow['temperature_blob'] as String),
        'ppo2': base64Decode(samplesRow['ppo2_blob'] as String),
        'cellMv0': base64Decode(samplesRow['cell_mv0_blob'] as String),
        'cellMv1': base64Decode(samplesRow['cell_mv1_blob'] as String),
        'cellMv2': base64Decode(samplesRow['cell_mv2_blob'] as String),
        'setpoint': base64Decode(samplesRow['setpoint_blob'] as String),
        'cns': base64Decode(samplesRow['cns_blob'] as String),
        'decoDepth': base64Decode(samplesRow['deco_depth_blob'] as String),
        'decoTime': base64Decode(samplesRow['deco_time_blob'] as String),
        'tts': base64Decode(samplesRow['tts_blob'] as String),
        'gasMixIdx': base64Decode(samplesRow['gas_mix_idx_blob'] as String),
        'status': base64Decode(samplesRow['status_blob'] as String),
        if (tankPressuresB64 != null)
          'tankPressures': base64Decode(tankPressuresB64),
      },
      diveId: diveId,
      sampleCount: samplesRow['sample_count'] as int,
      sampleIntervalMs: intervalMs,
    );
  }

  /// Get the raw binary blob for a dive (for re-parsing). Returns
  /// `null` when the device didn't import this dive — e.g. it arrived
  /// via cloud sync from another device. That's expected; raw blobs
  /// are intentionally device-local.
  Future<Uint8List?> getRawBlob(String diveId) async {
    final row = await (_drift.select(_drift.diveRawBlobs)
          ..where((t) => t.diveId.equals(diveId)))
        .getSingleOrNull();
    return row?.rawBlob;
  }

  /// Dives that haven't been exported to a Subsurface XML file yet,
  /// ordered by start time ascending. Excludes soft-deleted rows.
  Future<List<Dive>> getPendingSubsurfaceUploads() async {
    final rows = await _ps.getAll(
      'SELECT * FROM dives '
      'WHERE subsurface_uploaded_at IS NULL AND deleted_at IS NULL '
      'ORDER BY start_time ASC',
    );
    return rows.map(_rowToDive).toList();
  }

  /// Latest `subsurface_uploaded_at` (epoch seconds) across all live
  /// dives, or `null` if no dive has ever been pushed to Subsurface.
  /// Used by the Subsurface-sync settings card to render "Last synced".
  Future<int?> lastSubsurfaceUploadedAt() async {
    final row = await _ps.getOptional(
      'SELECT MAX(subsurface_uploaded_at) AS last FROM dives '
      'WHERE deleted_at IS NULL',
    );
    return row?['last'] as int?;
  }

  /// Stamps `subsurface_uploaded_at` on the given dives.
  Future<void> markSubsurfaceUploaded(
      Iterable<String> diveIds, int whenSeconds) async {
    final ids = diveIds.toList(growable: false);
    if (ids.isEmpty) return;
    await _ps.writeTransaction((tx) async {
      for (final id in ids) {
        final existing = await tx.getOptional(
            'SELECT version FROM dives WHERE id = ?', [id]);
        if (existing == null) continue;
        final newVersion = (existing['version'] as int? ?? 0) + 1;
        await tx.execute(
          'UPDATE dives SET owner_id = ?, subsurface_uploaded_at = ?, '
          'version = ? WHERE id = ?',
          [_ownerId, whenSeconds, newVersion, id],
        );
      }
    });
  }

  // ── Mapping ────────────────────────────────────────────────────────────

  /// Builds a Drift `Dive` row from a PowerSync result map. The legacy
  /// `rawBlob` field on the Drift class is filled with empty bytes —
  /// callers that need actual raw bytes use [getRawBlob].
  Dive _rowToDive(Map<String, dynamic> r) => Dive(
        id: r['id'] as String,
        dcSerial: r['dc_serial'] as int,
        dcDiveNumber: r['dc_dive_number'] as int,
        startTime: r['start_time'] as int,
        endTime: r['end_time'] as int,
        utcOffsetMinutes: r['utc_offset_minutes'] as int?,
        durationSeconds: r['duration_seconds'] as int,
        maxDepthMm: r['max_depth_mm'] as int,
        diveMode: r['dive_mode'] as int,
        decoModel: r['deco_model'] as int,
        gfLow: r['gf_low'] as int?,
        gfHigh: r['gf_high'] as int?,
        atmosphericPressureMbar: r['atmospheric_pressure_mbar'] as int,
        waterDensity: r['water_density'] as int,
        logVersion: r['log_version'] as int,
        dcModel: r['dc_model'] as int,
        dcFirmware: r['dc_firmware'] as int?,
        sampleIntervalMs: r['sample_interval_ms'] as int,
        gasMixesJson: r['gas_mixes_json'] as String,
        tanksJson: r['tanks_json'] as String?,
        sensorCalibrationJson: r['sensor_calibration_json'] as String?,
        configuredStackSeconds: r['configured_stack_seconds'] as int?,
        stackRemainingAtStartSeconds:
            r['stack_remaining_at_start_seconds'] as int?,
        stackRemainingAtEndSeconds:
            r['stack_remaining_at_end_seconds'] as int?,
        rawBlob: Uint8List(0),
        parserVersion: r['parser_version'] as int,
        importedAt: r['imported_at'] as int,
        subsurfaceUploadedAt: r['subsurface_uploaded_at'] as int?,
        deletedAt: r['deleted_at'] as int?,
      );
}
