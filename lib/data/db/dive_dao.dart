/// Data Access Object for dive CRUD operations.
///
/// Provides atomic import (single transaction for dive + samples),
/// deduplication by dive ID, and query methods.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../models/sample_set.dart';
import '../sample_codec/sample_codec.dart';
import '../../shearwater/parser/dive_converter.dart';
import 'database.dart';

/// DAO for dive import, query, and management.
class DiveDao {
  final AppDatabase _db;

  DiveDao(this._db);

  /// Atomically import a dive and its samples.
  ///
  /// Returns `true` if the dive was newly imported, `false` if it
  /// already exists (dedup by dive ID).
  Future<bool> importDive({
    required ConvertedDive converted,
    required Uint8List rawBlob,
    required int parserVersion,
  }) async {
    final dive = converted.dive;

    // Check for duplicate.
    final exists = await diveExists(dive.id);
    if (exists) return false;

    // Encode samples to column blobs.
    final sampleBlobs = SampleCodec.encode(converted.samples);

    // Gas mixes to JSON.
    final gasMixesJson =
        jsonEncode(dive.gasMixes.map((g) => g.toJson()).toList());

    // Tanks to JSON (null when no tanks logged).
    final tanksJson = dive.tanks.isEmpty
        ? null
        : jsonEncode(dive.tanks.map((t) => t.toJson()).toList());

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Atomic transaction: dive row + sample blobs.
    await _db.transaction(() async {
      await _db.into(_db.dives).insert(DivesCompanion.insert(
            id: dive.id,
            dcSerial: dive.dcSerial,
            dcDiveNumber: dive.dcDiveNumber,
            startTime: dive.startTime.millisecondsSinceEpoch ~/ 1000,
            endTime: dive.endTime.millisecondsSinceEpoch ~/ 1000,
            utcOffsetMinutes: Value(dive.utcOffsetMinutes),
            durationSeconds: dive.duration.inSeconds,
            maxDepthMm: (dive.maxDepthMeters * 1000).round(),
            diveMode: dive.diveMode.value,
            decoModel: dive.decoModel.value,
            gfLow: Value(dive.gfLow),
            gfHigh: Value(dive.gfHigh),
            atmosphericPressureMbar: dive.atmosphericPressureMbar,
            waterDensity: dive.waterDensityKgM3,
            logVersion: dive.logVersion,
            dcModel: dive.dcModel.index,
            sampleIntervalMs: dive.sampleIntervalMs,
            gasMixesJson: gasMixesJson,
            tanksJson: Value(tanksJson),
            configuredStackSeconds: Value(dive.configuredStackSeconds),
            stackRemainingAtStartSeconds:
                Value(dive.stackRemainingAtStartSeconds),
            stackRemainingAtEndSeconds:
                Value(dive.stackRemainingAtEndSeconds),
            rawBlob: rawBlob,
            parserVersion: parserVersion,
            importedAt: now,
          ));

      await _db.into(_db.diveSamples).insert(DiveSamplesCompanion.insert(
            diveId: dive.id,
            sampleCount: converted.samples.sampleCount,
            depthBlob: sampleBlobs['depth']!,
            temperatureBlob: sampleBlobs['temperature']!,
            ppo2Blob: sampleBlobs['ppo2']!,
            cellMv0Blob: sampleBlobs['cellMv0']!,
            cellMv1Blob: sampleBlobs['cellMv1']!,
            cellMv2Blob: sampleBlobs['cellMv2']!,
            setpointBlob: sampleBlobs['setpoint']!,
            cnsBlob: sampleBlobs['cns']!,
            decoDepthBlob: sampleBlobs['decoDepth']!,
            decoTimeBlob: sampleBlobs['decoTime']!,
            ttsBlob: sampleBlobs['tts']!,
            gasMixIdxBlob: sampleBlobs['gasMixIdx']!,
            statusBlob: sampleBlobs['status']!,
            tankPressuresBlob: Value(sampleBlobs['tankPressures']),
          ));
    });

    return true;
  }

  /// Check if a dive exists by ID.
  Future<bool> diveExists(String diveId) async {
    final query = _db.select(_db.dives)
      ..where((d) => d.id.equals(diveId))
      ..limit(1);
    final results = await query.get();
    return results.isNotEmpty;
  }

  /// Get all live dives ordered by start time descending (most recent first).
  /// Excludes soft-deleted rows.
  Future<List<Dive>> getAllDives() async {
    final query = _db.select(_db.dives)
      ..where((d) => d.deletedAt.isNull())
      ..orderBy([(d) => OrderingTerm.desc(d.startTime)]);
    return query.get();
  }

  /// Get a single dive by ID, or `null` if not found. Returns
  /// soft-deleted rows too — needed by the undo path.
  Future<Dive?> getDive(String id) async {
    final query = _db.select(_db.dives)..where((d) => d.id.equals(id));
    return query.getSingleOrNull();
  }

  /// Soft-deletes a dive. The row + raw blob stay on disk (so undo works
  /// and re-import lookups still detect duplicates); list queries
  /// filter it out.
  Future<void> softDeleteDive(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.dives)..where((d) => d.id.equals(id)))
        .write(DivesCompanion(deletedAt: Value(now)));
  }

  /// Clears the soft-delete flag — paired with the SnackBar UNDO action.
  Future<void> restoreDive(String id) async {
    await (_db.update(_db.dives)..where((d) => d.id.equals(id)))
        .write(const DivesCompanion(deletedAt: Value(null)));
  }

  /// Get the sample data for a dive.
  ///
  /// Returns `null` if the dive or its samples don't exist.
  Future<SampleSet?> getSamples(String diveId) async {
    final query = _db.select(_db.diveSamples)
      ..where((s) => s.diveId.equals(diveId));
    final row = await query.getSingleOrNull();
    if (row == null) return null;

    // Look up the sample interval from the dive record.
    final diveQuery = _db.select(_db.dives)
      ..where((d) => d.id.equals(diveId));
    final diveRow = await diveQuery.getSingleOrNull();
    final intervalMs = diveRow?.sampleIntervalMs ?? 10000;

    return SampleCodec.decode(
      blobs: {
        'depth': row.depthBlob,
        'temperature': row.temperatureBlob,
        'ppo2': row.ppo2Blob,
        'cellMv0': row.cellMv0Blob,
        'cellMv1': row.cellMv1Blob,
        'cellMv2': row.cellMv2Blob,
        'setpoint': row.setpointBlob,
        'cns': row.cnsBlob,
        'decoDepth': row.decoDepthBlob,
        'decoTime': row.decoTimeBlob,
        'tts': row.ttsBlob,
        'gasMixIdx': row.gasMixIdxBlob,
        'status': row.statusBlob,
        if (row.tankPressuresBlob != null)
          'tankPressures': row.tankPressuresBlob!,
      },
      diveId: diveId,
      sampleCount: row.sampleCount,
      sampleIntervalMs: intervalMs,
    );
  }

  /// Get the raw binary blob for a dive (for re-parsing).
  Future<Uint8List?> getRawBlob(String diveId) async {
    final query = _db.select(_db.dives)
      ..where((d) => d.id.equals(diveId));
    final row = await query.getSingleOrNull();
    return row?.rawBlob;
  }

  /// Dives that haven't been exported to a Subsurface XML file yet,
  /// ordered by start time ascending. Excludes soft-deleted rows.
  Future<List<Dive>> getPendingSubsurfaceUploads() async {
    final query = _db.select(_db.dives)
      ..where(
          (d) => d.subsurfaceUploadedAt.isNull() & d.deletedAt.isNull())
      ..orderBy([(d) => OrderingTerm.asc(d.startTime)]);
    return query.get();
  }

  /// Stamps `subsurfaceUploadedAt` on the given dives in one statement.
  Future<void> markSubsurfaceUploaded(
      Iterable<String> diveIds, int whenSeconds) async {
    final ids = diveIds.toList(growable: false);
    if (ids.isEmpty) return;
    await (_db.update(_db.dives)..where((d) => d.id.isIn(ids))).write(
      DivesCompanion(subsurfaceUploadedAt: Value(whenSeconds)),
    );
  }
}
