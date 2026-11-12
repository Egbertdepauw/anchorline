// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';
import 'dart:io';

import 'package:subsurface_core/data/sample_codec/sample_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../tool/site_showcase/lib/showcase.dart';
import '../../../tool/site_showcase/lib/showcase_db.dart';
import 'test_support.dart';

const _blobColumns = {
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

void main() {
  late Directory tmp;
  late String path;

  final sets = {
    'd1': makeSampleSet(
      diveId: 'd1',
      intervalMs: 10000,
      depth: [0.5, 10, 40, 0.5],
      ppo2: [0.7, 1.3, 1.3, 0.7],
      setpoint: [0.7, 1.3, 1.3, 0.7],
      cell0: [10, 55, 55, 10],
      cell1: [11, 56, 56, 11],
      decoDepth: [0, 0, 6, 0],
    ),
    'd2': makeSampleSet(
      diveId: 'd2',
      intervalMs: 10000,
      depth: [0.5, 20, 0.5],
      cell0: [10, 54, 10],
      decoDepth: [0, 3, 0],
    ),
  };

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('showcase_db_test');
    path = '${tmp.path}/powersync.db';
    final db = sqlite3.open(path);
    db.execute(
      'CREATE TABLE dives (id TEXT, dc_dive_number INTEGER, '
      'start_time INTEGER, duration_seconds INTEGER, max_depth_mm INTEGER, '
      'dive_mode INTEGER, sample_interval_ms INTEGER, deleted_at INTEGER)',
    );
    db.execute(
      'CREATE TABLE dive_samples (id TEXT, sample_count INTEGER, '
      '${_blobColumns.values.map((c) => '$c TEXT').join(', ')}, '
      'tank_pressures_blob TEXT)',
    );
    db.execute(
      'CREATE TABLE oxygen_cells (id TEXT, slot INTEGER, '
      'label TEXT, installed_date INTEGER, retired_date INTEGER, '
      'deleted_at INTEGER)',
    );
    void addDive(String id, int n, int start, int? deleted) {
      db.execute('INSERT INTO dives VALUES (?, ?, ?, ?, ?, ?, ?, ?)', [
        id,
        n,
        start,
        4000,
        40000,
        0,
        10000,
        deleted,
      ]);
    }

    addDive('d1', 1, 1000000, null);
    addDive('d2', 2, 2000000, null);
    addDive('gone', 3, 3000000, 1);
    for (final e in sets.entries) {
      final blobs = SampleCodec.encode(e.value);
      db.execute(
        'INSERT INTO dive_samples (id, sample_count, '
        '${_blobColumns.values.join(', ')}) VALUES '
        '(?, ?, ${List.filled(_blobColumns.length, '?').join(', ')})',
        [
          e.key,
          e.value.sampleCount,
          for (final k in _blobColumns.keys) base64Encode(blobs[k]!),
        ],
      );
    }
    db.execute(
      "INSERT INTO oxygen_cells VALUES ('c1', 1, 'Cell A', NULL, "
      'NULL, NULL)',
    );
    db.execute(
      "INSERT INTO oxygen_cells VALUES ('c2', 2, 'Gone', NULL, "
      'NULL, 5)',
    );
    db.close();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('reads non-deleted dives, cells and decoded samples', () {
    final db = SqliteShowcaseDb(path);
    addTearDown(db.close);
    final dives = db.dives..sort((a, b) => a.startTime.compareTo(b.startTime));
    expect(dives.map((d) => d.id), ['d1', 'd2']);
    expect(dives.first.diveNumber, 1);
    expect(dives.first.maxDepthMm, 40000);
    expect(dives.first.sampleIntervalMs, 10000);

    final cells = db.cells;
    expect(cells.single.id, 'c1');
    expect(cells.single.slot, 1);
    expect(cells.single.label, 'Cell A');

    for (final d in dives) {
      final got = db.samplesFor(d)!;
      final want = sets[d.id]!;
      expect(got.sampleCount, want.sampleCount);
      expect(got.sampleIntervalMs, 10000);
      expect(got.depthMeters, want.depthMeters);
      expect(got.ppo2Bar, want.ppo2Bar);
      expect(got.setpointBar, want.setpointBar);
      expect(got.cellMv0, want.cellMv0);
      expect(got.cellMv1, want.cellMv1);
      expect(got.decoStopDepthMeters, want.decoStopDepthMeters);
    }
  });

  test('buildShowcase works through the real SQLite reader', () {
    final db = SqliteShowcaseDb(path);
    addTearDown(db.close);
    // Both dives qualify as CCR; pin one so the test is order-independent.
    final r = buildShowcase(db: db, diveId: 'd1');
    expect(r.json['format'], 1);
    final dive = r.json['dive'] as Map;
    expect((dive['depthMeters'] as List).length, 4);
    expect((dive['cellMv'] as List).length, 3);
    expect(((dive['cellMv'] as List)[0] as List).length, 4);
    final cell = r.json['cell'] as Map;
    expect(cell['slot'], 1);
    expect((cell['points'] as List).length, 2);
    expect(r.cellId, 'c1');
  });

  test('null tank_pressures_blob decodes; other null blob skips the dive', () {
    final raw = sqlite3.open(path);
    raw.execute('UPDATE dive_samples SET tank_pressures_blob = NULL');
    raw.execute("UPDATE dive_samples SET cell_mv1_blob = NULL WHERE id = 'd2'");
    raw.close();
    final db = SqliteShowcaseDb(path);
    addTearDown(db.close);
    final dives = {for (final d in db.dives) d.id: d};
    expect(db.samplesFor(dives['d1']!)!.sampleCount, 4);
    expect(db.samplesFor(dives['d2']!), isNull);
  });

  test('CLI: missing --out is a usage error (exit 1)', () {
    final r = Process.runSync('dart', [
      'tool/site_showcase/export.dart',
      '--db',
      path,
    ]);
    expect(r.exitCode, 1);
    expect(r.stderr, contains('Missing --out'));
    final noDb = Process.runSync('dart', ['tool/site_showcase/export.dart']);
    expect(noDb.exitCode, 1);
    expect(noDb.stderr, contains('Missing --db'));
  });
}
