/// Read-only access to the PowerSync SQLite file for the showcase export.
///
/// The PowerSync file exposes `dives`, `dive_samples` and `oxygen_cells` as
/// views over `ps_data__*`; stock SQLite can read them. Sample blobs are
/// stored base64-encoded in text columns.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ccrlogger/data/models/sample_set.dart';
import 'package:ccrlogger/data/sample_codec/sample_codec.dart';
import 'package:sqlite3/sqlite3.dart';

/// One non-deleted dive; times are epoch seconds, depth is millimetres.
class DiveRow {
  const DiveRow({
    required this.id,
    required this.diveNumber,
    required this.startTime,
    required this.durationSeconds,
    required this.maxDepthMm,
    required this.diveMode,
    required this.sampleIntervalMs,
  });

  final String id;
  final int diveNumber;
  final int startTime;
  final int durationSeconds;
  final int maxDepthMm;

  /// Integer value of `DiveMode` (`lib/shearwater/parser/constants.dart`).
  final int diveMode;
  final int sampleIntervalMs;
}

/// One non-deleted oxygen cell; dates are epoch milliseconds (nullable).
class CellRow {
  const CellRow({
    required this.id,
    required this.slot,
    required this.label,
    required this.installedDate,
    required this.retiredDate,
  });

  final String id;

  /// 1-based sensor slot (1..3).
  final int slot;
  final String? label;
  final int? installedDate;
  final int? retiredDate;
}

abstract class ShowcaseDb {
  /// Non-deleted dives, any order.
  List<DiveRow> get dives;

  /// Non-deleted cells.
  List<CellRow> get cells;

  /// Decoded samples for [dive], or null when it has no sample row.
  SampleSet? samplesFor(DiveRow dive);

  void close() {}
}

class SqliteShowcaseDb implements ShowcaseDb {
  SqliteShowcaseDb(String path)
    : _db = sqlite3.open(path, mode: OpenMode.readOnly);

  final Database _db;

  static const _blobColumns = <String, String>{
    'depth': 'depth_blob',
    'temperature': 'temperature_blob',
    'ppo2': 'ppo2_blob',
    'cellMv0': 'cell_mv0_blob',
    'cellMv1': 'cell_mv1_blob',
    'cellMv2': 'cell_mv2_blob',
    'setpoint': 'setpoint_blob',
    'cns': 'cns_blob',
    'decoDepth': 'deco_depth_blob',
    'decoTime': 'deco_time_blob',
    'tts': 'tts_blob',
    'gasMixIdx': 'gas_mix_idx_blob',
    'status': 'status_blob',
  };

  @override
  List<DiveRow> get dives => [
    for (final r in _db.select(
      'SELECT id, dc_dive_number, start_time, duration_seconds, '
      'max_depth_mm, dive_mode, sample_interval_ms '
      'FROM dives WHERE deleted_at IS NULL',
    ))
      DiveRow(
        id: r['id'] as String,
        diveNumber: (r['dc_dive_number'] as int?) ?? 0,
        startTime: r['start_time'] as int,
        durationSeconds: (r['duration_seconds'] as int?) ?? 0,
        maxDepthMm: (r['max_depth_mm'] as int?) ?? 0,
        diveMode: (r['dive_mode'] as int?) ?? -1,
        sampleIntervalMs: (r['sample_interval_ms'] as int?) ?? 1000,
      ),
  ];

  @override
  List<CellRow> get cells => [
    for (final r in _db.select(
      'SELECT id, slot, label, installed_date, retired_date '
      'FROM oxygen_cells WHERE deleted_at IS NULL',
    ))
      CellRow(
        id: r['id'] as String,
        slot: r['slot'] as int,
        label: r['label'] as String?,
        installedDate: r['installed_date'] as int?,
        retiredDate: r['retired_date'] as int?,
      ),
  ];

  @override
  SampleSet? samplesFor(DiveRow dive) {
    final rows = _db.select('SELECT * FROM dive_samples WHERE id = ?', [
      dive.id,
    ]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final blobs = <String, Uint8List>{};
    for (final e in _blobColumns.entries) {
      final v = row[e.value];
      if (v is! String) {
        stderr.writeln(
          'Warning: skipping dive ${dive.id}: ${e.value} is NULL.',
        );
        return null;
      }
      blobs[e.key] = base64Decode(v);
    }
    final tank = row['tank_pressures_blob'];
    if (tank is String && tank.isNotEmpty) {
      blobs['tankPressures'] = base64Decode(tank);
    }
    return SampleCodec.decode(
      blobs: blobs,
      diveId: dive.id,
      sampleCount: row['sample_count'] as int,
      sampleIntervalMs: dive.sampleIntervalMs,
    );
  }

  @override
  void close() => _db.close();
}
