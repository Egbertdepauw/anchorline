import 'dart:typed_data';
import 'package:ccrlogger/analysis/deco/zhl16c.dart';
import 'package:ccrlogger/analysis/deco/replay_result.dart';
import 'package:ccrlogger/data/models/dive.dart' show DiveGasMix;
import 'package:flutter_test/flutter_test.dart';

SampleStub _flat(double depthM, int durationSec, int intervalMs) {
  final n = (durationSec * 1000 / intervalMs).round();
  return SampleStub(
    depthMeters: Float32List(n)..fillRange(0, n, depthM),
    gasMixIndex: Uint8List(n),
    sampleIntervalMs: intervalMs,
  );
}

void main() {
  group('Zhl16cReplay — basic invariants', () {
    test('surface-equilibrated diver at 0 m → GF99 ≈ 0', () {
      final samples = _flat(0, 60, 1000);
      final result = Zhl16cReplay().run(
        samples: samples,
        gasMixes: [
          DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: true)
        ],
        gfLow: 30,
        gfHigh: 85,
      );
      expect(result.gf99Series[0], lessThan(1.0));
      expect(result.surfaceGfFinal, lessThan(1.0));
    });

    test('30 min at 30 m on air → tissues take up gas, GF99 rises', () {
      final samples = _flat(30, 30 * 60, 10000);
      final result = Zhl16cReplay().run(
        samples: samples,
        gasMixes: [
          DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: true)
        ],
        gfLow: 30,
        gfHigh: 85,
      );
      expect(result.gf99Series.last, greaterThan(30.0));
    });

    test('result has 16 tissue series each with correct length', () {
      final samples = _flat(20, 60, 1000);
      final result = Zhl16cReplay().run(
        samples: samples,
        gasMixes: [
          DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: true)
        ],
        gfLow: 30,
        gfHigh: 85,
      );
      expect(result.tissueLoadsPct, hasLength(16));
      for (final series in result.tissueLoadsPct) {
        expect(series.length, samples.depthMeters.length);
      }
    });

    test('GF99 series length matches sample count', () {
      final samples = _flat(20, 60, 1000);
      final result = Zhl16cReplay().run(
        samples: samples,
        gasMixes: [
          DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: true)
        ],
        gfLow: 30,
        gfHigh: 85,
      );
      expect(result.gf99Series.length, samples.depthMeters.length);
      expect(result.ceilingMeters.length, samples.depthMeters.length);
    });

    test('algorithm field on result is zhl16c', () {
      final samples = _flat(20, 60, 1000);
      final result = Zhl16cReplay().run(
        samples: samples,
        gasMixes: [
          DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: true)
        ],
        gfLow: 30,
        gfHigh: 85,
      );
      expect(result.algorithm, DecoAlgorithm.zhl16c);
      expect(result.gfLow, 30);
      expect(result.gfHigh, 85);
    });
  });
}
