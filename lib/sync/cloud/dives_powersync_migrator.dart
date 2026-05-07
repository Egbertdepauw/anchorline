/// One-shot Drift → PowerSync migration for existing dive data.
///
/// Pre-Phase-2.5 builds wrote dives + samples + raw blobs to Drift's
/// `dives` / `dive_samples` tables. Post-Phase-2.5, dives + samples
/// live in PowerSync (so they sync across devices) and raw blobs in
/// Drift's new local-only `dive_raw_blobs` table.
///
/// On every app start we run this migrator. It iterates Drift's
/// pre-existing `dives` rows; for each id missing from PowerSync, it
/// copies metadata + samples in (sample blobs base64-encoded for the
/// text-only PowerSync columns) and parks the raw blob in
/// `dive_raw_blobs`. Idempotent — re-running after migration is a no-op
/// for already-migrated rows.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:powersync/powersync.dart';

import '../../data/db/database.dart';
import 'ccrlogger_backend_connector.dart' show SessionSource;

class DivesPowerSyncMigrator {
  final AppDatabase _drift;
  final PowerSyncDatabase _ps;
  final SessionSource _session;

  DivesPowerSyncMigrator(this._drift, this._ps, this._session);

  /// Copies any Drift `dives` row whose id is missing from PowerSync.
  /// Returns the number of dives migrated.
  Future<int> migrate() async {
    final ownerId = _session.currentSession?.user.id;
    final driftDives = await _drift.select(_drift.dives).get();
    if (driftDives.isEmpty) return 0;

    var migrated = 0;
    for (final dive in driftDives) {
      final exists = await _ps.getOptional(
          'SELECT id FROM dives WHERE id = ?', [dive.id]);
      if (exists != null) continue;

      final samples = await (_drift.select(_drift.diveSamples)
            ..where((s) => s.diveId.equals(dive.id)))
          .getSingleOrNull();
      if (samples == null) {
        debugPrint(
            'DivesPowerSyncMigrator: skipping ${dive.id} — no samples row');
        continue;
      }

      final nowMs = DateTime.now().millisecondsSinceEpoch;

      await _ps.writeTransaction((tx) async {
        await tx.execute(
          'INSERT INTO dives '
          '(id, owner_id, dc_serial, dc_dive_number, start_time, end_time, '
          'utc_offset_minutes, duration_seconds, max_depth_mm, dive_mode, '
          'deco_model, gf_low, gf_high, atmospheric_pressure_mbar, '
          'water_density, log_version, dc_model, dc_firmware, '
          'sample_interval_ms, gas_mixes_json, tanks_json, '
          'configured_stack_seconds, stack_remaining_at_start_seconds, '
          'stack_remaining_at_end_seconds, parser_version, imported_at, '
          'subsurface_uploaded_at, deleted_at, version, sync_status) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '
          '?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            dive.id,
            ownerId,
            dive.dcSerial,
            dive.dcDiveNumber,
            dive.startTime,
            dive.endTime,
            dive.utcOffsetMinutes,
            dive.durationSeconds,
            dive.maxDepthMm,
            dive.diveMode,
            dive.decoModel,
            dive.gfLow,
            dive.gfHigh,
            dive.atmosphericPressureMbar,
            dive.waterDensity,
            dive.logVersion,
            dive.dcModel,
            dive.dcFirmware,
            dive.sampleIntervalMs,
            dive.gasMixesJson,
            dive.tanksJson,
            dive.configuredStackSeconds,
            dive.stackRemainingAtStartSeconds,
            dive.stackRemainingAtEndSeconds,
            dive.parserVersion,
            dive.importedAt,
            dive.subsurfaceUploadedAt,
            dive.deletedAt,
            1,
            0,
          ],
        );
        await tx.execute(
          'INSERT INTO dive_samples '
          '(id, owner_id, sample_count, depth_blob, temperature_blob, '
          'ppo2_blob, cell_mv0_blob, cell_mv1_blob, cell_mv2_blob, '
          'setpoint_blob, cns_blob, deco_depth_blob, deco_time_blob, '
          'tts_blob, gas_mix_idx_blob, status_blob, tank_pressures_blob, '
          'created_at, updated_at, version, sync_status) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            dive.id,
            ownerId,
            samples.sampleCount,
            base64Encode(samples.depthBlob),
            base64Encode(samples.temperatureBlob),
            base64Encode(samples.ppo2Blob),
            base64Encode(samples.cellMv0Blob),
            base64Encode(samples.cellMv1Blob),
            base64Encode(samples.cellMv2Blob),
            base64Encode(samples.setpointBlob),
            base64Encode(samples.cnsBlob),
            base64Encode(samples.decoDepthBlob),
            base64Encode(samples.decoTimeBlob),
            base64Encode(samples.ttsBlob),
            base64Encode(samples.gasMixIdxBlob),
            base64Encode(samples.statusBlob),
            samples.tankPressuresBlob == null
                ? null
                : base64Encode(samples.tankPressuresBlob!),
            nowMs,
            nowMs,
            1,
            0,
          ],
        );
      });

      // Park the raw blob locally so re-parse-after-parser-bug-fix still
      // works on this device.
      await _drift.into(_drift.diveRawBlobs).insertOnConflictUpdate(
            DiveRawBlobsCompanion.insert(
              diveId: dive.id,
              rawBlob: dive.rawBlob,
            ),
          );

      migrated++;
    }
    if (migrated > 0) {
      debugPrint(
          'DivesPowerSyncMigrator: copied $migrated Drift dives → PowerSync');
    }
    return migrated;
  }
}
