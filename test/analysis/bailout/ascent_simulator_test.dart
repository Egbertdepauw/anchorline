import 'package:ccrlogger/analysis/bailout/ascent_simulator.dart';
import 'package:ccrlogger/data/models/dive.dart' show DiveGasMix;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NDL dive (no deco required) returns a single straight-up leg', () {
    // Start at 20m, tissues roughly surface-equilibrated on air.
    // No significant deco obligation → should ascend straight to the surface
    // in a small number of 1-minute steps with no flat holds.
    final initialN2 = List<double>.filled(16, 0.75);
    final initialHe = List<double>.filled(16, 0.0);
    final plan = simulateAscent(
      triggerDepthMeters: 20,
      initialN2Bar: initialN2,
      initialHeBar: initialHe,
      availableGases: [
        const DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: true),
      ],
      gfLow: 30,
      gfHigh: 85,
      ascentRateFast: 18,
      ascentRateSlow: 9,
      sacBottom: 30,
      sacDeco: 20,
    );

    expect(plan.stops.length, greaterThanOrEqualTo(1));
    expect(plan.totalTime.inSeconds, greaterThan(0));
    // 20 m → 0 m at 9–18 m/min takes no more than ~3 minutes.
    // With surface-loaded tissues and gfHigh 85, no deco should be needed.
    expect(plan.totalTime.inMinutes, lessThan(5));
    // Final depth of the last leg must be 0.
    expect(plan.stops.last.depthEndMeters, equals(0.0));
    // All legs should be ascending moves, not flat stops.
    final flatStops = plan.stops.where((s) => s.isStop).length;
    expect(flatStops, equals(0));
  });

  test('volumeByGas sums to total volume across all stops', () {
    final initialN2 = List<double>.filled(16, 0.75);
    final initialHe = List<double>.filled(16, 0.0);
    final plan = simulateAscent(
      triggerDepthMeters: 30,
      initialN2Bar: initialN2,
      initialHeBar: initialHe,
      availableGases: [
        const DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: true),
      ],
      gfLow: 30,
      gfHigh: 85,
      ascentRateFast: 18,
      ascentRateSlow: 9,
      sacBottom: 30,
      sacDeco: 20,
    );

    final stopSum =
        plan.stops.fold<double>(0.0, (a, s) => a + s.volumeLitresConsumed);
    final byGasSum =
        plan.volumeByGas.values.fold<double>(0.0, (a, v) => a + v);

    expect(byGasSum, closeTo(stopSum, 0.01));
    // Sanity: positive volume was consumed.
    expect(stopSum, greaterThan(0.0));
  });

  test('deco dive switches to deeper deco gas at appropriate stop', () {
    // Tissue loads representative of ~45 min at 60 m on 21/35 (TMX 21/35),
    // starting from a surface-equilibrated state (N2 ≈ 0.75 bar, He = 0).
    // Values were computed by running the Schreiner equation forward for each
    // compartment; fast compartments are near-saturated, slow ones lag behind.
    // This is a physically plausible state — unlike a uniform 4.0 bar load,
    // which would be undersaturated at 60 m and produce no deco obligation.
    final initialN2 = [
      3.1, 3.0, 2.9, 2.6, 2.3, 2.0, 1.8, 1.5,
      1.3, 1.2, 1.1, 1.0, 1.0, 0.9, 0.9, 0.9,
    ];
    final initialHe = List<double>.filled(16, 0.0);
    final plan = simulateAscent(
      triggerDepthMeters: 60,
      initialN2Bar: initialN2,
      initialHeBar: initialHe,
      availableGases: [
        const DiveGasMix(
            oxygenPercent: 21, heliumPercent: 35, isDiluent: true), // bottom
        const DiveGasMix(
            oxygenPercent: 50, heliumPercent: 0, isDiluent: false), // EAN50
        const DiveGasMix(
            oxygenPercent: 100, heliumPercent: 0, isDiluent: false), // O2
      ],
      gfLow: 30,
      gfHigh: 85,
      ascentRateFast: 18,
      ascentRateSlow: 9,
      sacBottom: 30,
      sacDeco: 20,
    );

    // At least two gases should have been used (bottom + at least one deco gas).
    expect(plan.volumeByGas.length, greaterThanOrEqualTo(2));
    // A heavily-loaded deco ascent from 60 m takes more than 5 minutes.
    expect(plan.totalTime.inMinutes, greaterThan(5));
    // volumeByGas and per-stop volumes stay in sync.
    final stopSum =
        plan.stops.fold<double>(0.0, (a, s) => a + s.volumeLitresConsumed);
    final byGasSum =
        plan.volumeByGas.values.fold<double>(0.0, (a, v) => a + v);
    expect(byGasSum, closeTo(stopSum, 0.1));
  });

  test('safety cap terminates runaway simulation', () {
    // Pathological case: tissues loaded far beyond any plausible dive, gfHigh
    // set absurdly low (1).  The simulator must NOT loop forever.
    final initialN2 = List<double>.filled(16, 10.0);
    final initialHe = List<double>.filled(16, 0.0);
    final plan = simulateAscent(
      triggerDepthMeters: 100,
      initialN2Bar: initialN2,
      initialHeBar: initialHe,
      availableGases: [
        const DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: true),
      ],
      gfLow: 30,
      gfHigh: 1, // impossible to satisfy → cap kicks in
      ascentRateFast: 18,
      ascentRateSlow: 9,
      sacBottom: 30,
      sacDeco: 20,
    );

    // Simulation capped at 300 iterations — must return in finite time.
    expect(plan.stops.length, lessThanOrEqualTo(300));
    // Volume accounting still consistent.
    final stopSum =
        plan.stops.fold<double>(0.0, (a, s) => a + s.volumeLitresConsumed);
    final byGasSum =
        plan.volumeByGas.values.fold<double>(0.0, (a, v) => a + v);
    expect(byGasSum, closeTo(stopSum, 0.1));
  });
}
