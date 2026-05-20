import 'package:ccrlogger/analysis/planner/plan_simulator.dart';
import 'package:ccrlogger/data/models/dive_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('square 30 m / 20 min on 21/35 dil at SP 1.3 loads compartments above '
      'surface', () {
    final out = simulatePlan(
      gases: const [
        DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
      ],
      segments: const [
        DivePlanSegment(
            depthMeters: 30,
            durationMinutes: 20,
            gasMixIndex: 0,
            setpoint: 1.3),
      ],
      mode: DivePlanMode.cc,
      descentRateMpm: 18,
      ascentRateMpm: 9,
      bottomSetpoint: 1.3,
      ascentSetpoint: 0.7,
      decoSetpoint: 1.4,
    );
    // N2 in the fast compartments must have risen above 0.75 bar (surface).
    expect(out.triggerN2Bar[0], greaterThan(0.75));
    expect(out.triggerN2Bar[3], greaterThan(0.75));
    // He must have risen above 0 in the fast compartments.
    expect(out.triggerHeBar[0], greaterThan(0));
    // Trigger depth = the deepest segment with time > 0.
    expect(out.triggerDepthMeters, 30);
    // Bottom-time before trigger > 0.
    expect(out.totalRuntime.inMinutes, greaterThan(20));
  });

  test('empty segments returns surface-equivalent trigger state', () {
    final out = simulatePlan(
      gases: const [],
      segments: const [],
      mode: DivePlanMode.cc,
      descentRateMpm: 18,
      ascentRateMpm: 9,
      bottomSetpoint: 1.3,
      ascentSetpoint: 0.7,
      decoSetpoint: 1.4,
    );
    expect(out.triggerDepthMeters, 0);
    expect(out.triggerN2Bar.every((n2) => (n2 - 0.745).abs() < 0.01), isTrue);
  });

  test('time-0 setpoint change updates active SP without advancing time', () {
    final out = simulatePlan(
      gases: const [
        DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
      ],
      segments: const [
        DivePlanSegment(
            depthMeters: 50,
            durationMinutes: 20,
            gasMixIndex: 0,
            setpoint: 0.7),
        DivePlanSegment(
            depthMeters: 50, durationMinutes: 0, gasMixIndex: 0, setpoint: 1.3),
        DivePlanSegment(
            depthMeters: 50,
            durationMinutes: 10,
            gasMixIndex: 0,
            setpoint: 1.3),
      ],
      mode: DivePlanMode.cc,
      descentRateMpm: 18,
      ascentRateMpm: 9,
      bottomSetpoint: 1.3,
      ascentSetpoint: 0.7,
      decoSetpoint: 1.4,
    );
    // Total time = descent (50m / 18 = 2.78 min ≈ 167 s) + 20 min + 10 min.
    // Allow ±1 s rounding tolerance.
    expect(out.totalRuntime.inSeconds, closeTo(167 + 30 * 60, 2));
  });

  test('multi-level dive: deeper segment + shallower segment',
      () {
    final out = simulatePlan(
      gases: const [
        DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
      ],
      segments: const [
        DivePlanSegment(
            depthMeters: 50,
            durationMinutes: 15,
            gasMixIndex: 0,
            setpoint: 1.3),
        DivePlanSegment(
            depthMeters: 30,
            durationMinutes: 20,
            gasMixIndex: 0,
            setpoint: 1.3),
      ],
      mode: DivePlanMode.cc,
      descentRateMpm: 18,
      ascentRateMpm: 9,
      bottomSetpoint: 1.3,
      ascentSetpoint: 0.7,
      decoSetpoint: 1.4,
    );
    expect(out.triggerDepthMeters, 50,
        reason: 'trigger = deepest segment, even if shallower segments '
            'are later in the dive');
  });

  test('CNS accumulates above zero at high PPO2 / depth', () {
    final out = simulatePlan(
      gases: const [
        DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
      ],
      segments: const [
        DivePlanSegment(
            depthMeters: 50,
            durationMinutes: 30,
            gasMixIndex: 0,
            setpoint: 1.4),
      ],
      mode: DivePlanMode.cc,
      descentRateMpm: 18,
      ascentRateMpm: 9,
      bottomSetpoint: 1.4,
      ascentSetpoint: 0.7,
      decoSetpoint: 1.4,
    );
    expect(out.cnsPercent, greaterThan(0));
    expect(out.otuTotal, greaterThan(0));
    expect(out.maxDensityGramsPerLitre, greaterThan(2.5));
  });
}
