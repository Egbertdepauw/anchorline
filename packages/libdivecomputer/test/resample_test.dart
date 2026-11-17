import 'package:libdivecomputer/libdivecomputer.dart';
import 'package:libdivecomputer/src/mapping/resample.dart';
import 'package:test/test.dart';

import 'support/builders.dart';

void main() {
  test('rows every 10 s land on a 10 s grid unchanged', () {
    final r = resample([
      row(0, depth: 0, temp: 20),
      row(10000, depth: 5, temp: 19),
      row(20000, depth: 10, temp: 18),
    ]);
    expect(r.intervalMs, 10000);
    expect(r.count, 3);
    expect(r.depth, [0, 5, 10]);
    expect(r.temperature, [20, 19, 18]);
  });

  test('a missing sample is interpolated for depth and carried forward for '
      'the rest', () {
    // The row at 10 s has only a temperature; the 20 s row has everything.
    final r = resample([
      row(0, depth: 0, temp: 20, cns: 0.1),
      row(10000, temp: 19),
      row(20000, depth: 10, temp: 18, cns: 0.2),
      row(30000, depth: 10),
    ]);
    expect(r.depth, [0, 5, 10, 10]);
    expect(r.temperature, [20, 19, 18, 18]);
    expect(r.cns[1], closeTo(0.1, 1e-6));
    expect(r.cns[2], closeTo(0.2, 1e-6));
    expect(r.cns[3], closeTo(0.2, 1e-6));
  });

  test('setpoint and gas logged only on change are carried forward', () {
    final r = resample(
      [
        row(0, depth: 0, setpoint: 0.7, gas: 0),
        row(10000, depth: 5),
        row(20000, depth: 10),
        row(30000, depth: 10, setpoint: 1.3, gas: 1),
        row(40000, depth: 10),
      ],
      tankIndexes: [0],
    );
    expect(r.setpoint, [
      closeTo(0.7, 1e-6),
      closeTo(0.7, 1e-6),
      closeTo(0.7, 1e-6),
      closeTo(1.3, 1e-6),
      closeTo(1.3, 1e-6),
    ]);
    expect(r.gasMixIndex, [0, 0, 0, 1, 1]);
  });

  test('the interval is the most common gap, not the smallest', () {
    // Times 0, 4, 8, 12, 13 s: gaps 4, 4, 4, 1.
    final r = resample([
      row(0, depth: 0),
      row(4000, depth: 4),
      row(8000, depth: 8),
      row(12000, depth: 12),
      row(13000, depth: 13),
    ]);
    expect(r.intervalMs, 4000);
    // The grid covers the last row: 0, 4, 8, 12, 16 s.
    expect(r.count, 5);
    expect(r.depth, [0, 4, 8, 12, 13]);
  });

  test('every column has exactly count entries, also with no values', () {
    final r = resample(
      [row(0), row(5000), row(10000)],
      tankIndexes: [0, 1],
    );
    expect(r.count, 3);
    for (final c in [
      r.depth,
      r.temperature,
      r.ppo2,
      r.setpoint,
      r.cns,
      r.decoStopDepth,
    ]) {
      expect(c.length, 3);
    }
    expect(r.decoTime.length, 3);
    expect(r.tts.length, 3);
    expect(r.gasMixIndex.length, 3);
    expect(r.tankPressures, hasLength(2));
    expect(r.tankPressures.every((c) => c.length == 3), isTrue);
    expect(r.cellPpo2, isEmpty);
  });

  test('the median of the cells is the ppO2 when nothing is voted', () {
    final r = resample([
      row(0, depth: 0, cells: {0: 0.98, 1: 1.0, 2: 1.02, 3: 1.1}),
      row(10000, depth: 1, cells: {0: 1.0}),
    ]);
    expect(r.cellPpo2, hasLength(4));
    expect(r.ppo2[0], closeTo(1.01, 1e-6));
    // Cells carry forward individually: 1.0, 1.0, 1.02, 1.1 -> 1.01.
    expect(r.ppo2[1], closeTo(1.01, 1e-6));
    expect(r.cellPpo2[0][1], closeTo(1.0, 1e-6));
    expect(r.cellPpo2[3][1], closeTo(1.1, 1e-6));
  });

  test('a gas translation that returns null keeps the previous index', () {
    final r = resample(
      [
        row(0, depth: 0, gas: 0),
        row(10000, depth: 1, gas: 1),
        row(20000, depth: 1, gas: 2),
      ],
      gasIndex: (i) => i == 1 ? null : (i == 2 ? 1 : 0),
    );
    expect(r.gasMixIndex, [0, 0, 1]);
  });

  test('deco: stop depth only for DECOSTOP and DEEPSTOP', () {
    final r = resample([
      row(
        0,
        depth: 0,
        deco: const LibdcDeco(
          type: LibdcDecoType.ndl,
          timeSeconds: 600,
          depthM: 0,
          ttsSeconds: 0,
        ),
      ),
      row(
        10000,
        depth: 30,
        deco: const LibdcDeco(
          type: LibdcDecoType.decoStop,
          timeSeconds: 120,
          depthM: 6,
          ttsSeconds: 900,
        ),
      ),
      row(
        20000,
        depth: 30,
        deco: const LibdcDeco(
          type: LibdcDecoType.safetyStop,
          timeSeconds: 60,
          depthM: 5,
          ttsSeconds: 60,
        ),
      ),
    ]);
    expect(r.decoStopDepth, [0, 6, 0]);
    expect(r.decoTime, [600, 120, 60]);
    expect(r.tts, [0, 900, 60]);
  });

  test('before the first row every channel holds its first value', () {
    final r = resample(
      [
        row(
          10000,
          depth: 1,
          temp: 21,
          ppo2: 0.7,
          setpoint: 0.7,
          gas: 1,
          cns: 0.1,
          cells: {0: 0.7},
          pressures: {0: 200},
        ),
        row(20000, depth: 2),
      ],
      tankIndexes: [0],
    );
    expect(r.count, 3);
    expect(r.temperature[0], 21);
    expect(r.ppo2[0], closeTo(0.7, 1e-6));
    expect(r.setpoint[0], closeTo(0.7, 1e-6));
    expect(r.gasMixIndex[0], 1);
    expect(r.cns[0], closeTo(0.1, 1e-6));
    expect(r.cellPpo2[0][0], closeTo(0.7, 1e-6));
    expect(r.tankPressures[0][0], 200);
    expect(r.depth[0], 1);
  });

  test('a corrupt row time beyond the dive time is a dataFormat failure', () {
    expect(
      () => resample([
        row(0, depth: 0),
        row(1000, depth: 1),
        row(2000, depth: 1),
        row(1 << 31, depth: 0),
      ], diveTimeSeconds: 600),
      throwsA(
        isA<LibdcParseException>().having(
          (e) => e.status,
          'status',
          LibdcStatus.dataFormat,
        ),
      ),
    );
  });

  test('rows at the same time keep their delivery order', () {
    final a = row(10000, depth: 1, temp: 1);
    final b = row(10000, depth: 1, temp: 2);
    final out = rowsInTimeOrder([row(20000), a, b, row(0)]);
    expect(out.indexOf(a) < out.indexOf(b), isTrue);
    expect(out.map((r) => r.timeMs), [0, 10000, 10000, 20000]);
    final r = resample([row(0, temp: 0), a, b]);
    expect(r.temperature[1], 2);
  });
}
