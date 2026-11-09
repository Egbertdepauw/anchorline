// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';

import 'package:ccrlogger/data/models/sample_set.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/site_showcase/lib/showcase.dart';
import '../../../tool/site_showcase/lib/showcase_db.dart';
import 'test_support.dart';

class FakeDb implements ShowcaseDb {
  FakeDb(this.dives, this.cells, this.samples);
  @override
  final List<DiveRow> dives;
  @override
  final List<CellRow> cells;
  final Map<String, dynamic> samples;

  @override
  SampleSet? samplesFor(DiveRow dive) => samples[dive.id] as SampleSet?;

  @override
  void close() {}
}

const _ccr = 0;
const _oc = 1;

DiveRow _row(
  String id,
  int n,
  int start, {
  int mode = _ccr,
  int dur = 5400,
  int depthMm = 48000,
}) => DiveRow(
  id: id,
  diveNumber: n,
  startTime: start,
  durationSeconds: dur,
  maxDepthMm: depthMm,
  diveMode: mode,
  sampleIntervalMs: 10000,
);

void _checkNoForbiddenKeys(Object? v) {
  const forbidden = {'id', 'date', 'serial', 'notes', 'site', 'buddy', 'name'};
  if (v is Map) {
    for (final e in v.entries) {
      expect(forbidden.contains(e.key), isFalse, reason: 'key ${e.key}');
      _checkNoForbiddenKeys(e.value);
    }
  } else if (v is List) {
    v.forEach(_checkNoForbiddenKeys);
  }
}

void main() {
  test('decimate: 25 samples at 1 s -> 3 points', () {
    final depth = List<double>.generate(25, (i) => i.toDouble());
    final set = makeSampleSet(
      diveId: 'x',
      intervalMs: 1000,
      depth: depth,
      ppo2: List<double>.generate(25, (i) => i < 10 ? 1.0 : 1.2),
      setpoint: List<double>.generate(25, (i) => i < 10 ? 0.7 : 1.3),
      cell0: List<double>.filled(25, 0),
      cell1: List<double>.filled(25, 10),
    );
    final d = decimate(set, 10000);
    expect(d.intervalSeconds, 10);
    expect(d.depthMeters, [9.0, 19.0, 24.0]);
    expect(d.ppo2Bar, [1.0, 1.2, 1.2]);
    expect(d.setpointBar, [0.7, 1.3, 1.3]);
    expect(d.cellMv[0], [null, null, null]);
    expect(d.cellMv[1], [10.0, 10.0, 10.0]);
  });

  test('buildShowcase picks the CCR dive with deco; JSON is anonymous', () {
    const n = 540; // 90 min at 10 s
    List<double> prof(double max) => List<double>.generate(
      n,
      (i) => i < 20 ? 0.5 : (i > n - 20 ? 0.5 : max),
    );
    final deep = makeSampleSet(
      diveId: 'deep',
      intervalMs: 10000,
      depth: prof(48),
      ppo2: List<double>.filled(n, 1.3),
      setpoint: List<double>.filled(n, 1.3),
      cell0: List<double>.filled(n, 55.55),
      cell1: List<double>.filled(n, 54.321),
      cell2: List<double>.filled(n, 0),
      decoDepth: List<double>.generate(n, (i) => i > 100 ? 6 : 0),
    );
    final shallow = makeSampleSet(
      diveId: 'shallow',
      intervalMs: 10000,
      depth: prof(10),
      cell0: List<double>.filled(n, 50),
    );
    final cells = [
      CellRow(
        id: 'c1',
        slot: 1,
        label: 'Cell A',
        installedDate: null,
        retiredDate: null,
      ),
      CellRow(
        id: 'c2',
        slot: 2,
        label: 'Cell B',
        installedDate: null,
        retiredDate: null,
      ),
    ];
    final db = FakeDb(
      [
        _row('shallow', 2, 2000000, dur: 1800, depthMm: 10000),
        _row('deep', 1, 1000000),
        _row('ocdeep', 3, 3000000, mode: _oc),
      ],
      cells,
      {'deep': deep, 'shallow': shallow, 'ocdeep': deep},
    );
    final r = buildShowcase(db: db);
    expect(r.diveId, 'deep');
    expect(r.json['format'], 1);
    expect(r.summary, contains('Cell'));
    final text = jsonEncode(r.json);
    expect(text.length, lessThan(100 * 1024));
    _checkNoForbiddenKeys(jsonDecode(text));
    expect(text, isNot(contains('Cell A')));
    expect(text, isNot(contains('deep"')));
    final dive = r.json['dive'] as Map;
    expect(
      dive['durationSeconds'],
      ((dive['depthMeters'] as List).length - 1) *
          (dive['intervalSeconds'] as int),
    );
    expect((dive['depthMeters'] as List).length, n);
    expect((dive['cellMv'] as List).length, 3);
    expect((dive['cellMv'] as List)[2].first, isNull);
    expect(dive['maxDepthMeters'], 48.0);
  });

  test('buildShowcase auto-picks the cell with the most dives', () {
    List<double> d() => [0.5, 0.5, 30, 30];
    DiveRow row(String id, int n) => _row(id, n, 1000000 + n * 100000);
    final samples = <String, dynamic>{};
    final dives = <DiveRow>[];
    for (var i = 1; i <= 6; i++) {
      dives.add(row('d$i', i));
      samples['d$i'] = makeSampleSet(
        diveId: 'd$i',
        intervalMs: 10000,
        depth: d(),
        cell0: [10, 10, 60, 60],
        // slot 2 only reads in the first three dives
        cell1: i <= 3 ? [10, 10, 60, 60] : [0, 0, 0, 0],
        decoDepth: [0, 0, 3, 3],
      );
    }
    final db = FakeDb(dives, [
      CellRow(
        id: 'b',
        slot: 2,
        label: 'B',
        installedDate: null,
        retiredDate: null,
      ),
      CellRow(
        id: 'a',
        slot: 1,
        label: 'A',
        installedDate: null,
        retiredDate: null,
      ),
    ], samples);
    final r = buildShowcase(db: db);
    expect(r.cellId, 'a');
    final cell = r.json['cell'] as Map;
    expect(cell['slot'], 1);
    final pts = cell['points'] as List;
    expect(pts.length, 6);
    expect(pts.first, {'dive': 1, 'day': 0, 'surfaceMv': 10.0, 'peakMv': 60.0});
    expect((pts[1] as Map)['day'], 1);
  });

  test('a dive with a peak but no surface samples yields no cell point', () {
    final samples = <String, dynamic>{};
    final dives = <DiveRow>[];
    for (var i = 1; i <= 3; i++) {
      dives.add(_row('d$i', i, 1000000 + i * 86400));
      samples['d$i'] = makeSampleSet(
        diveId: 'd$i',
        intervalMs: 10000,
        depth: [0.5, 0.5, 30, 30],
        // Dive 2 has no reading at the surface, only at depth.
        cell0: i == 2 ? [0, 0, 60, 60] : [10, 10, 60, 60],
        decoDepth: [0, 0, 3, 3],
      );
    }
    final db = FakeDb(dives, [
      CellRow(
        id: 'a',
        slot: 1,
        label: 'A',
        installedDate: null,
        retiredDate: null,
      ),
    ], samples);
    final pts = (buildShowcase(db: db).json['cell'] as Map)['points'] as List;
    expect(pts.length, 2);
    expect([for (final p in pts) (p as Map)['dive']], [1, 2]);
    expect([for (final p in pts) (p as Map)['day']], [0, 2]);
    for (final p in pts) {
      expect((p as Map)['surfaceMv'], isNotNull);
    }
  });

  test('cell means are rounded once (10.249 -> 10.2, not 10.3)', () {
    final set = makeSampleSet(
      diveId: 'x',
      intervalMs: 10000,
      depth: [5],
      ppo2: [1.2349],
      cell0: [10.249],
    );
    final d = decimate(set, 10000);
    expect(d.cellMv[0], [10.2]);
    expect(d.ppo2Bar, [1.23]);
  });
}
