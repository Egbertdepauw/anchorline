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

  test('CCR plan stamps the deco setpoint on every diveAscent leg', () {
    final result = runPlan(
      gases: const [
        DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
        DivePlanGas(oxygenPercent: 50, heliumPercent: 0, isDiluent: false),
      ],
      segments: const [
        DivePlanSegment(
            depthMeters: 40,
            durationMinutes: 25,
            gasMixIndex: 0,
            setpoint: 1.3),
      ],
      bailout: const [],
      mode: DivePlanMode.cc,
      gfLow: 30,
      gfHigh: 85,
      useVpmb: false,
      vpmbConservatism: 2,
      ascentRateMpm: 9,
      descentRateMpm: 18,
      bottomSetpoint: 1.3,
      ascentSetpoint: 0.7,
      decoSetpoint: 1.5,
      lastStopDepthMeters: 6,
      availableTanks: const [kAl40, kAl80],
    );
    expect(result.diveAscent, isNotEmpty);
    expect(result.diveAscent.every((s) => s.setpointBar == 1.5), isTrue,
        reason: 'CCR deco legs must carry decoSetpoint=1.5');
    // Last stop at 6 m → no stop should be emitted at 3 m.
    final stopDepths = result.diveAscent
        .where((s) => s.isStop)
        .map((s) => s.depthStartMeters)
        .toSet();
    expect(stopDepths.contains(3.0), isFalse,
        reason: 'lastStopDepthMeters=6 must skip the 3 m stop');
  });

  test('borderline dive with lastStop=6 never emits a 3 m stop', () {
    // A 30 m / 20 min CCR Air dive at GF 50/95 sits on the borderline
    // between NDL and a few minutes of deco. With lastStop=6 the
    // shallowest emitted stop must be 6 m — even if Phase 1 would have
    // picked 3 m.
    final result = runPlan(
      gases: const [
        DivePlanGas(oxygenPercent: 21, heliumPercent: 0, isDiluent: true),
      ],
      segments: const [
        DivePlanSegment(
            depthMeters: 30,
            durationMinutes: 20,
            gasMixIndex: 0,
            setpoint: 1.3),
      ],
      bailout: const [],
      mode: DivePlanMode.cc,
      gfLow: 50,
      gfHigh: 95,
      useVpmb: false,
      vpmbConservatism: 2,
      ascentRateMpm: 9,
      descentRateMpm: 18,
      bottomSetpoint: 1.3,
      ascentSetpoint: 0.7,
      decoSetpoint: 1.5,
      lastStopDepthMeters: 6,
      availableTanks: const [kAl40, kAl80],
    );
    final stopDepths = result.diveAscent
        .where((s) => s.isStop)
        .map((s) => s.depthStartMeters)
        .toSet();
    expect(stopDepths.contains(3.0), isFalse,
        reason: 'lastStop=6 must prevent any 3 m stop');
  });

  test('CCR descent uses ascent setpoint, not bottom setpoint', () {
    // Petrel / MultiDeco convention: the high "bottom" SP only applies
    // once the diver reaches the working depth. Descent (and inter-
    // segment transits) use the low transit / ascent SP.
    final result = runPlan(
      gases: const [
        DivePlanGas(oxygenPercent: 21, heliumPercent: 0, isDiluent: true),
      ],
      segments: const [
        DivePlanSegment(
            depthMeters: 30,
            durationMinutes: 20,
            gasMixIndex: 0,
            setpoint: 1.3),
      ],
      bailout: const [],
      mode: DivePlanMode.cc,
      gfLow: 50,
      gfHigh: 95,
      useVpmb: false,
      vpmbConservatism: 2,
      ascentRateMpm: 9,
      descentRateMpm: 18,
      bottomSetpoint: 1.3,
      ascentSetpoint: 0.7,
      decoSetpoint: 1.5,
      lastStopDepthMeters: 6,
      availableTanks: const [kAl40, kAl80],
    );
    // First profile leg is the descent — must carry ascentSetpoint.
    expect(result.profile.first.depthStartMeters, 0);
    expect(result.profile.first.setpointBar, 0.7,
        reason: 'descent must use ascentSetpoint');
    // Second profile leg is the level segment — must carry bottomSetpoint
    // (which the segment supplied as its own setpoint, 1.3).
    expect(result.profile[1].setpointBar, 1.3,
        reason: 'level segment uses its declared setpoint');
  });

  test('CCR deco hold is short — earlier regression bug saw 53 min at 6 m '
      'because Phase 2 _advanceOneStep calls forgot to pass setpointBar', () {
    // 30 m / 30 min Air-CC at SP 1.3 bottom / SP 1.5 deco, GF 50/95.
    // With the OC fallback bug, the 6 m stop ran ~53 min. With CCR
    // math (loop is ≈ pure O₂ at 6 m on SP 1.5), the hold should be
    // under 15 min.
    final result = runPlan(
      gases: const [
        DivePlanGas(oxygenPercent: 21, heliumPercent: 0, isDiluent: true),
      ],
      segments: const [
        DivePlanSegment(
            depthMeters: 30,
            durationMinutes: 30,
            gasMixIndex: 0,
            setpoint: 1.3),
      ],
      bailout: const [],
      mode: DivePlanMode.cc,
      gfLow: 50,
      gfHigh: 95,
      useVpmb: false,
      vpmbConservatism: 2,
      ascentRateMpm: 9,
      descentRateMpm: 18,
      bottomSetpoint: 1.3,
      ascentSetpoint: 0.7,
      decoSetpoint: 1.5,
      lastStopDepthMeters: 6,
      availableTanks: const [kAl40, kAl80],
    );
    final holdAt6 = result.diveAscent
        .where((s) => s.isStop && s.depthStartMeters == 6.0)
        .map((s) => s.duration.inMinutes)
        .fold<int>(0, (a, b) => a + b);
    expect(holdAt6, lessThan(15),
        reason: '6 m hold on CCR loop must not stretch to 50 min');
  });

  test('borderline single-stop dive uses gfHigh at the hold (MultiDeco '
      'convention)', () {
    // 30 m / 30 min CCR Air at GF 50/95 with lastStop=6 m: Phase 1 lands
    // a single 6 m stop. Standard Erik-Baker would apply gfLow here and
    // hold ~10 min; MultiDeco/Petrel apply gfHigh and emit ~40 s. We
    // match the latter so the planner doesn't disagree with the
    // user's MultiDeco numbers on this very common case.
    final result = runPlan(
      gases: const [
        DivePlanGas(oxygenPercent: 21, heliumPercent: 0, isDiluent: true),
      ],
      segments: const [
        DivePlanSegment(
            depthMeters: 30,
            durationMinutes: 30,
            gasMixIndex: 0,
            setpoint: 1.3),
      ],
      bailout: const [],
      mode: DivePlanMode.cc,
      gfLow: 50,
      gfHigh: 95,
      useVpmb: false,
      vpmbConservatism: 2,
      ascentRateMpm: 9,
      descentRateMpm: 18,
      bottomSetpoint: 1.3,
      ascentSetpoint: 0.7,
      decoSetpoint: 1.3,
      lastStopDepthMeters: 6,
      availableTanks: const [kAl40, kAl80],
    );
    final holdAt6Sec = result.diveAscent
        .where((s) => s.isStop && s.depthStartMeters == 6.0)
        .map((s) => s.duration.inSeconds)
        .fold<int>(0, (a, b) => a + b);
    expect(holdAt6Sec, lessThanOrEqualTo(120),
        reason: '6 m hold must be ≤ 2 min on a borderline NDL dive '
            '(MultiDeco gives 40 s for an equivalent plan)');
  });

  test('OC plan leaves setpointBar null on diveAscent legs', () {
    final result = runPlan(
      gases: const [
        DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: false),
      ],
      segments: const [
        DivePlanSegment(
            depthMeters: 40, durationMinutes: 25, gasMixIndex: 0),
      ],
      bailout: const [],
      mode: DivePlanMode.oc,
      gfLow: 30,
      gfHigh: 85,
      useVpmb: false,
      vpmbConservatism: 2,
      ascentRateMpm: 9,
      descentRateMpm: 18,
      bottomSetpoint: 1.3,
      ascentSetpoint: 0.7,
      decoSetpoint: 1.5,
      lastStopDepthMeters: 3,
      availableTanks: const [kAl40, kAl80],
    );
    expect(result.diveAscent.every((s) => s.setpointBar == null), isTrue);
  });
}
