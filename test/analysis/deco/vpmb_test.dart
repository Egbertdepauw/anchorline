import 'dart:typed_data';
import 'package:ccrlogger/analysis/deco/vpmb.dart';
import 'package:ccrlogger/analysis/deco/zhl16c.dart' show SampleStub;
import 'package:ccrlogger/analysis/deco/replay_result.dart';
import 'package:ccrlogger/analysis/deco/vpmb_constants.dart';
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
  group('vpmbGradientFactor', () {
    test('conservatism 0 → 1.0', () {
      expect(vpmbGradientFactor(0), closeTo(1.0, 0.001));
    });
    test('conservatism 2 → 0.75', () {
      expect(vpmbGradientFactor(2), closeTo(0.75, 0.001));
    });
    test('conservatism 4 → 0.5', () {
      expect(vpmbGradientFactor(4), closeTo(0.5, 0.001));
    });
    test('clamps negative + over-range', () {
      expect(vpmbGradientFactor(-5), 1.0);
      expect(vpmbGradientFactor(99), 0.5);
    });
  });

  group('VpmbReplay — basic invariants', () {
    test('result has algorithm == vpmb and conservatism populated', () {
      final samples = _flat(20, 60, 1000);
      final result = VpmbReplay().run(
        samples: samples,
        gasMixes: [
          DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: true)
        ],
        conservatism: 2,
      );
      expect(result.algorithm, DecoAlgorithm.vpmb);
      expect(result.vpmbConservatism, 2);
      expect(result.gfLow, isNull);
      expect(result.gfHigh, isNull);
    });

    test('result series lengths match sample count', () {
      final samples = _flat(20, 60, 1000);
      final result = VpmbReplay().run(
        samples: samples,
        gasMixes: [
          DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: true)
        ],
        conservatism: 2,
      );
      expect(result.gf99Series.length, samples.depthMeters.length);
      expect(result.ceilingMeters.length, samples.depthMeters.length);
      expect(result.tissueLoadsPct, hasLength(16));
    });

    test('higher conservatism → higher maxGf99 on the same dive', () {
      final samples = _flat(40, 30 * 60, 10000);
      final lo = VpmbReplay().run(
        samples: samples,
        gasMixes: [
          DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: true)
        ],
        conservatism: 0,
      );
      final hi = VpmbReplay().run(
        samples: samples,
        gasMixes: [
          DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: true)
        ],
        conservatism: 4,
      );
      // More conservative (allowedFactor smaller) → numerator/denominator ratio larger.
      expect(hi.maxGf99, greaterThan(lo.maxGf99));
    });
  });
}
