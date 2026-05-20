import 'package:ccrlogger/analysis/bailout/tank_recommender.dart'
    show kAl40, kAl80;
import 'package:ccrlogger/analysis/planner/plan_runner.dart';
import 'package:ccrlogger/data/models/dive_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('40 m / 20 min CC dive on 21/35 produces a non-empty deco schedule '
      'and a non-trivial bailout plan', () {
    final result = runPlan(
      gases: const [
        DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
        DivePlanGas(oxygenPercent: 50, heliumPercent: 0, isDiluent: false),
      ],
      segments: const [
        DivePlanSegment(
            depthMeters: 40,
            durationMinutes: 20,
            gasMixIndex: 0,
            setpoint: 1.3),
      ],
      bailout: const [
        DivePlanBailoutBottle(
            gasMixIndex: 0, waterCapacityL: 5.7, fillPressureBar: 200),
        DivePlanBailoutBottle(
            gasMixIndex: 1, waterCapacityL: 5.7, fillPressureBar: 232),
      ],
      mode: DivePlanMode.cc,
      gfLow: 30,
      gfHigh: 85,
      useVpmb: false,
      vpmbConservatism: 2,
      ascentRateMpm: 9,
      descentRateMpm: 18,
      bottomSetpoint: 1.3,
      ascentSetpoint: 0.7,
      decoSetpoint: 1.4,
      lastStopDepthMeters: 6,
      availableTanks: const [kAl40, kAl80],
    );
    expect(result.diveAscent, isNotEmpty);
    expect(result.bailout.perGas, isNotEmpty);
    expect(result.cnsPercent, greaterThan(0));
    expect(result.totalRuntime.inMinutes, greaterThanOrEqualTo(20));
  });

  test('NDL dive (no deco required) returns empty schedule but still '
      'computes a bailout plan', () {
    final result = runPlan(
      gases: const [
        DivePlanGas(oxygenPercent: 21, heliumPercent: 0, isDiluent: true),
      ],
      segments: const [
        DivePlanSegment(
            depthMeters: 15,
            durationMinutes: 10,
            gasMixIndex: 0,
            setpoint: 1.0),
      ],
      bailout: const [
        DivePlanBailoutBottle(
            gasMixIndex: 0, waterCapacityL: 5.7, fillPressureBar: 200),
      ],
      mode: DivePlanMode.cc,
      gfLow: 30, gfHigh: 85, useVpmb: false, vpmbConservatism: 2,
      ascentRateMpm: 9, descentRateMpm: 18,
      bottomSetpoint: 1.0, ascentSetpoint: 0.7, decoSetpoint: 1.4,
      lastStopDepthMeters: 6, availableTanks: const [kAl40, kAl80],
    );
    expect(result.diveAscent, isEmpty,
        reason: 'NDL → planDeco returns []');
  });
}
