import 'package:ccrlogger/analysis/blending/gas_blender.dart';
import 'package:flutter_test/flutter_test.dart';

const _eps = 0.5; // bar — fills round to 1-bar precision anyway

void main() {
  group('planBlend — ideal gas', () {
    test('empty cylinder → Tx 18/45 @ 200 bar topped with air', () {
      // Bookkeeping at 200 bar target on Tx 18/45 with air topoff:
      //   He pp target = 0.45 × 200 = 90 bar
      //   N2 pp target = 0.37 × 200 = 74 bar → air topoff = 74 / 0.79 ≈ 93.7 bar
      //   O2 pp target = 0.18 × 200 = 36 bar → O2 add = 36 - 0.21 × 93.7 ≈ 16.3 bar
      final r = planBlend(
        current: const CylinderState(
            oxygenPercent: 21,
            heliumPercent: 0,
            pressureBar: 0,
            waterCapacityL: 12),
        target: const CylinderState(
            oxygenPercent: 18,
            heliumPercent: 45,
            pressureBar: 200,
            waterCapacityL: 12),
        topoff: FillSource.air,
        useRealGas: false,
      );
      expect(r.isOk, isTrue);
      expect(r.steps.length, equals(3));
      // He first by default.
      expect(r.steps[0].kind, BlendStepKind.addHe);
      expect(r.steps[0].barAdded, closeTo(90, _eps));
      // Then O2.
      expect(r.steps[1].kind, BlendStepKind.addO2);
      expect(r.steps[1].barAdded, closeTo(16.3, _eps));
      // Then topoff.
      expect(r.steps[2].kind, BlendStepKind.addTopoff);
      expect(r.steps[2].barAdded, closeTo(93.7, _eps));
      expect(r.finalPressureBar, closeTo(200, _eps));
      expect(r.drainToPressureBar, isNull);
    });

    test('partial 50 bar of Tx 21/35 → Tx 18/45 @ 200 bar (no drain)', () {
      // Current pp: He=17.5, O2=10.5, N2=22.0
      // Target pp: He=90, O2=36, N2=74
      // He add = 72.5; N2 add via air = 52 → air = 65.8; O2 add = 11.7
      final r = planBlend(
        current: const CylinderState(
            oxygenPercent: 21,
            heliumPercent: 35,
            pressureBar: 50,
            waterCapacityL: 12),
        target: const CylinderState(
            oxygenPercent: 18,
            heliumPercent: 45,
            pressureBar: 200,
            waterCapacityL: 12),
        topoff: FillSource.air,
        useRealGas: false,
      );
      expect(r.isOk, isTrue);
      expect(r.steps[0].barAdded, closeTo(72.5, _eps));
      expect(r.steps[1].barAdded, closeTo(11.7, _eps));
      expect(r.steps[2].barAdded, closeTo(65.8, _eps));
      expect(r.finalPressureBar, closeTo(200, _eps));
    });

    test('100 bar of air → Tx 18/45 @ 200 bar needs a drain (too much N2)',
        () {
      // Air at 100 bar: N2 pp = 79. Target N2 pp = 74. Over by 5 bar →
      // drain to 74/79 × 100 = 93.7 bar first.
      final r = planBlend(
        current: const CylinderState(
            oxygenPercent: 21,
            heliumPercent: 0,
            pressureBar: 100,
            waterCapacityL: 12),
        target: const CylinderState(
            oxygenPercent: 18,
            heliumPercent: 45,
            pressureBar: 200,
            waterCapacityL: 12),
        topoff: FillSource.air,
        useRealGas: false,
      );
      expect(r.isOk, isTrue);
      expect(r.drainToPressureBar, isNotNull);
      expect(r.drainToPressureBar!, closeTo(93.7, _eps));
      // First step is the drain.
      expect(r.steps.first.kind, BlendStepKind.drain);
      expect(r.steps.first.barAdded, lessThan(0));
    });

    test('cost accounting: He litres × price + O2 litres × price', () {
      // 12-litre cylinder, 90 bar He = 1080 barliter at the blending
      // temperature (ideal-gas: n × R × T cancels back to bar × volume).
      // 16.3 bar O2 ≈ 196 barliter. Air = flat 5.
      final r = planBlend(
        current: const CylinderState(
            oxygenPercent: 21,
            heliumPercent: 0,
            pressureBar: 0,
            waterCapacityL: 12),
        target: const CylinderState(
            oxygenPercent: 18,
            heliumPercent: 45,
            pressureBar: 200,
            waterCapacityL: 12),
        topoff: FillSource.air,
        useRealGas: false,
        prices: const BlendPrices(
          oxygenPerLitre: 0.05,
          heliumPerLitre: 0.10,
          airFlatFee: 5,
        ),
      );
      expect(r.cost.heliumLitres, closeTo(1080, 6));
      expect(r.cost.heliumCost, closeTo(108, 1));
      expect(r.cost.oxygenLitres, closeTo(196, 6));
      expect(r.cost.airCost, equals(5));
      expect(r.cost.total, closeTo(108 + 196 * 0.05 + 5, 1));
    });

    test('fill sequence: o2-then-topoff-then-he reorders the steps', () {
      final r = planBlend(
        current: const CylinderState(
            oxygenPercent: 21,
            heliumPercent: 0,
            pressureBar: 0,
            waterCapacityL: 12),
        target: const CylinderState(
            oxygenPercent: 18,
            heliumPercent: 45,
            pressureBar: 200,
            waterCapacityL: 12),
        topoff: FillSource.air,
        useRealGas: false,
        sequence: FillSequence.o2ThenTopoffThenHe,
      );
      expect(r.steps[0].kind, BlendStepKind.addO2);
      expect(r.steps[1].kind, BlendStepKind.addTopoff);
      expect(r.steps[2].kind, BlendStepKind.addHe);
      // The cumulative pressures at each step differ from the default
      // sequence, but the FINAL pressure must still be 200.
      expect(r.finalPressureBar, closeTo(200, _eps));
    });

    test('EAN32 top-off changes the O2 + air contribution', () {
      // Empty → EAN 32 @ 200 bar with EAN32 topoff. All from EAN32 bank.
      // Since current = empty and target = EAN32, the blender should
      // ONLY top-off (no O2 / He bottle needed).
      final r = planBlend(
        current: const CylinderState(
            oxygenPercent: 21,
            heliumPercent: 0,
            pressureBar: 0,
            waterCapacityL: 12),
        target: const CylinderState(
            oxygenPercent: 32,
            heliumPercent: 0,
            pressureBar: 200,
            waterCapacityL: 12),
        topoff: const FillSource(oxygenPercent: 32, heliumPercent: 0),
        useRealGas: false,
      );
      expect(r.isOk, isTrue);
      // Only the topoff step should appear (no O2 / He bottle).
      expect(r.steps.length, equals(1));
      expect(r.steps.first.kind, BlendStepKind.addTopoff);
      expect(r.steps.first.barAdded, closeTo(200, _eps));
    });
  });

  group('planBlend — real gas', () {
    test('vdW shifts the He / air split on a Tx 21/35 fill', () {
      // Reference (blender-toolkit.t-provider.de) for empty 12 L → Tx
      // 21/35 @ 250 bar, air top-off, 18 °C, vdW: He = 82.4 bar, O2 =
      // 22.9 bar, air = 144.7 bar (sum = 250 ✓). Our vdW with simple
      // mole-weighted mixing rules should land within a couple of bar
      // of that — and crucially, sum to 250.
      final r = planBlend(
        current: const CylinderState(
            oxygenPercent: 21,
            heliumPercent: 0,
            pressureBar: 0,
            waterCapacityL: 12),
        target: const CylinderState(
            oxygenPercent: 21,
            heliumPercent: 35,
            pressureBar: 250,
            waterCapacityL: 12),
        topoff: FillSource.air,
        useRealGas: true,
      );
      expect(r.isOk, isTrue);
      expect(r.steps.length, equals(3));
      expect(r.steps.first.kind, BlendStepKind.addHe);
      expect(r.steps[1].kind, BlendStepKind.addO2);
      expect(r.steps[2].kind, BlendStepKind.addTopoff);
      // Sum-to-target — the bug we just fixed (was 257).
      expect(r.finalPressureBar, closeTo(250, 0.5));
      // Helium leg within ~3 bar of the reference's 82.4.
      expect(r.steps.first.barAdded, closeTo(82.4, 3.0));
    });

    test('hot-fill compensation: filling at 35 °C for a 20 °C target '
        'overshoots the gauge by the temperature ratio', () {
      // 250 bar (cold) target. Filling warm at 35 °C should land the
      // gauge at ~250 × (35+273)/(20+273) ≈ 263 bar during the fill.
      final r = planBlend(
        current: const CylinderState(
            oxygenPercent: 21,
            heliumPercent: 0,
            pressureBar: 0,
            waterCapacityL: 12),
        target: const CylinderState(
            oxygenPercent: 32,
            heliumPercent: 0,
            pressureBar: 250,
            waterCapacityL: 12),
        topoff: FillSource.air,
        useRealGas: false, // ideal so the ratio is clean
        temperatureKelvin: 35 + 273.15,
        settledTemperatureKelvin: 20 + 273.15,
      );
      expect(r.isOk, isTrue);
      // Final HOT fill pressure should be the settled × T_hot/T_cold ratio.
      final expected = 250 * (35 + 273.15) / (20 + 273.15);
      expect(r.finalPressureBar, closeTo(expected, 1.0));
      // settledPressureBar reports the cold target.
      expect(r.settledPressureBar, equals(250));
      // Sum of all step deltas equals the hot fill pressure.
      var sum = 0.0;
      for (final s in r.steps) {
        sum += s.barAdded;
      }
      expect(sum, closeTo(expected, 1.0));
    });

    test('real gas and ideal gas produce different fill plans on Tx 21/35', () {
      // Same blend, two modes — the per-step bars must differ.
      const cur = CylinderState(
          oxygenPercent: 21,
          heliumPercent: 0,
          pressureBar: 0,
          waterCapacityL: 12);
      const tgt = CylinderState(
          oxygenPercent: 21,
          heliumPercent: 35,
          pressureBar: 250,
          waterCapacityL: 12);
      final ideal = planBlend(
          current: cur, target: tgt, topoff: FillSource.air, useRealGas: false);
      final real = planBlend(
          current: cur, target: tgt, topoff: FillSource.air, useRealGas: true);
      expect((real.steps.first.barAdded - ideal.steps.first.barAdded).abs(),
          greaterThan(0.5),
          reason: 'He bar should differ between ideal and real gas');
      // Both must still sum to the target.
      expect(ideal.finalPressureBar, closeTo(250, 0.5));
      expect(real.finalPressureBar, closeTo(250, 0.5));
    });
  });
}
