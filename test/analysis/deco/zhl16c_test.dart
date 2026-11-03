import 'dart:typed_data';
import 'package:ccrlogger/analysis/deco/gas_pressures.dart';
import 'package:ccrlogger/analysis/deco/zhl16c.dart';
import 'package:ccrlogger/analysis/deco/replay_result.dart';
import 'package:subsurface_core/data/models/dive.dart' show DiveGasMix;
import 'package:flutter_test/flutter_test.dart';

SampleStub _flat(double depthM, int durationSec, int intervalMs,
    {double setpointBar = 0.0}) {
  final n = (durationSec * 1000 / intervalMs).round();
  return SampleStub(
    depthMeters: Float32List(n)..fillRange(0, n, depthM),
    gasMixIndex: Uint8List(n),
    sampleIntervalMs: intervalMs,
    setpointBar: Float32List(n)..fillRange(0, n, setpointBar),
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

    test(
        'CCR setpoint 1.3 at 30 m on 18/45 diluent loads far less N2 than OC '
        'would (Surface GF 115% bug reproducer)', () {
      // 30 min at 30 m. OC on 18/45 trimix vs CCR with setpoint 1.3 bar.
      // CCR keeps PPO2 at 1.3 the whole time, so the share of inerts in
      // the loop is much smaller than the diluent's own fN2/fHe at depth.
      final gas = DiveGasMix(oxygenPercent: 18, heliumPercent: 45, isDiluent: true);

      final ocResult = Zhl16cReplay().run(
        samples: _flat(30, 30 * 60, 10000),
        gasMixes: [gas],
        gfLow: 50,
        gfHigh: 95,
      );
      final ccrResult = Zhl16cReplay().run(
        samples: _flat(30, 30 * 60, 10000, setpointBar: 1.3),
        gasMixes: [gas],
        gfLow: 50,
        gfHigh: 95,
      );

      // CCR with PPO2 1.3 must produce a smaller surface GF than OC on
      // the same diluent — fewer inerts in the breathing loop.
      expect(ccrResult.surfaceGfFinal, lessThan(ocResult.surfaceGfFinal));
      expect(ccrResult.maxGf99, lessThan(ocResult.maxGf99));
    });

    test('CCR setpoint exceeding ambient at shallow depth → no N2 on-gassing',
        () {
      // 6 m on air diluent, but the setpoint is 1.3 bar — more than the
      // depth itself can provide. Inert headroom should clip to zero, so
      // the diver is effectively breathing pure O2.
      final samples = _flat(6, 30 * 60, 10000, setpointBar: 1.3);
      final result = Zhl16cReplay().run(
        samples: samples,
        gasMixes: [
          DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: true)
        ],
        gfLow: 50,
        gfHigh: 95,
      );
      // No N2 loading → tissues stay at or below the surface equilibrium.
      // GF99 must NOT rise above its starting value.
      expect(result.gf99Series.last, lessThan(1.0));
      expect(result.surfaceGfFinal, lessThan(1.0));
    });

    test('exposes finalN2Bar and finalHeBar (16 elements each)', () {
      final result = Zhl16cReplay().run(
        samples: _flat(30, 30 * 60, 10000),
        gasMixes: [
          DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: true)
        ],
        gfLow: 50,
        gfHigh: 95,
      );
      expect(result.finalN2Bar, hasLength(16));
      expect(result.finalHeBar, hasLength(16));
      // On air, He stays at zero; N2 loads on the faster compartments.
      expect(result.finalHeBar.every((p) => p == 0.0), isTrue);
      expect(result.finalN2Bar.first, greaterThan(surfaceEquilibriumN2Bar));
    });

    test(
        'surfacePressureBar parameter shifts SurfGF — feeding the dive '
        "computer's recorded barometric pressure (instead of the 1.013 "
        'default) is what closes the gap with Subsurface', () {
      // Identical samples; only the surface-pressure parameter changes.
      // The same tissue load is being evaluated against a different
      // M-value at surface, so SurfGF and the per-sample GF99 must differ.
      final samples = _flat(30, 30 * 60, 10000);
      const gas = [
        DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: true)
      ];

      final defaultRun = Zhl16cReplay().run(
        samples: samples,
        gasMixes: gas,
        gfLow: 30,
        gfHigh: 85,
      );
      final highPressureRun = Zhl16cReplay().run(
        samples: samples,
        gasMixes: gas,
        gfLow: 30,
        gfHigh: 85,
        surfacePressureBar: 1.030,
      );

      // Higher surface pressure ⇒ less supersaturation at surface for the
      // same tissue load ⇒ lower SurfGF. The direction matters: the bug
      // we're fixing has us over-reporting SurfGF because we assume a
      // lower surface pressure than the diver actually surfaced into.
      expect(
        highPressureRun.surfaceGfFinal,
        lessThan(defaultRun.surfaceGfFinal),
        reason: 'a higher recorded surface pressure must produce a '
            'lower SurfGF for the same dive profile',
      );
      // Same direction on the running GF99 trace (last sample).
      expect(
        highPressureRun.gf99Series.last,
        lessThan(defaultRun.gf99Series.last),
      );
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

    test('NaN setpoint (merged-dive surface gap) does not poison GF', () {
      // A merged dive inserts a flat surface block with NaN setpoint where the
      // computer logged nothing. The replay must treat that as SP-off (OC) and
      // keep producing finite GF instead of NaN — otherwise surfaceGf.round()
      // throws "Infinity or NaN toInt".
      const n = 60;
      final depth = Float32List(n)..fillRange(0, n, 20.0);
      final setpoint = Float32List(n)..fillRange(0, n, 1.2);
      for (var i = 20; i < 40; i++) {
        depth[i] = 0.0;
        setpoint[i] = double.nan;
      }
      final samples = SampleStub(
        depthMeters: depth,
        gasMixIndex: Uint8List(n),
        sampleIntervalMs: 10000,
        setpointBar: setpoint,
      );
      final result = Zhl16cReplay().run(
        samples: samples,
        gasMixes: [
          DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: true)
        ],
        gfLow: 30,
        gfHigh: 85,
      );
      expect(result.surfaceGfFinal.isNaN, isFalse);
      expect(result.maxGf99.isNaN, isFalse);
      expect(result.gf99Series.every((g) => !g.isNaN), isTrue);
    });
  });
}
