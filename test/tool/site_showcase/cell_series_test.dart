// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/site_showcase/lib/cell_series.dart';
import 'test_support.dart';

void main() {
  DiveSamples dive(String id, int day, {required List<double> cell0}) {
    // depth: first 3 samples at the surface, then 2 deep.
    final depth = [0.2, 0.5, 0.9, 20.0, 30.0];
    return (
      diveId: id,
      date: DateTime.utc(2026, 1, day),
      samples: makeSampleSet(
        diveId: id,
        intervalMs: 1000,
        depth: depth,
        cell0: cell0,
      ),
    );
  }

  test('surface = mean of surface samples >= 5 mV, peak = max >= 5 mV', () {
    final dives = [
      // Surface (depth < 1 m) readings 10 and 12; the 2 is below 5 mV.
      dive('a', 1, cell0: [10, 12, 2, 50, 60]),
      dive('b', 2, cell0: [9, 9, 9, 40, 70]),
      dive('c', 3, cell0: [8, 10, 12, 55, 61.5]),
    ];
    final r = mvSeriesForSlot(dives, 0);
    expect(r.surface.map((p) => p.diveId), ['a', 'b', 'c']);
    expect(r.surface[0].mv, closeTo(11.0, 1e-6)); // (10+12)/2, 2 filtered
    expect(r.surface[1].mv, closeTo(9.0, 1e-6));
    expect(r.surface[2].mv, closeTo(10.0, 1e-6));
    expect(r.peak.map((p) => p.mv), [60.0, 70.0, 61.5]);
    expect(r.surface[0].date, DateTime.utc(2026, 1, 1));
  });

  test('a dive whose slot is all zero contributes no point', () {
    final dives = [
      dive('a', 1, cell0: [10, 10, 10, 50, 60]),
      dive('b', 2, cell0: [0, 0, 0, 0, 0]),
      dive('c', 3, cell0: [10, 10, 10, 50, 60]),
    ];
    final r = mvSeriesForSlot(dives, 0);
    expect(r.surface.map((p) => p.diveId), ['a', 'c']);
    expect(r.peak.map((p) => p.diveId), ['a', 'c']);
  });

  test('a peak without in-record surface samples gives a peak only', () {
    final dives = [
      dive('a', 1, cell0: [2, 3, 4, 50, 60]),
    ];
    final r = mvSeriesForSlot(dives, 0);
    expect(r.surface, isEmpty);
    expect(r.peak.single.mv, 60.0);
  });
}
