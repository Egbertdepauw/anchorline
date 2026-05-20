/// Orchestrates the full plan computation:
///   simulator → trigger tissues → planDeco → planBailout → PlanResult.
library;

import 'dart:math' as math;

import '../bailout/ascent_simulator.dart' show AscentStop;
import '../bailout/bailout_planner.dart' show planBailout;
import '../bailout/tank_recommender.dart' show TankSpec;
import '../deco/deco_planner.dart' show planDeco;
import '../../data/models/dive.dart' show DiveGasMix;
import '../../data/models/dive_plan.dart';
import 'plan_result.dart';
import 'plan_simulator.dart';

PlanResult runPlan({
  required List<DivePlanGas> gases,
  required List<DivePlanSegment> segments,
  required List<DivePlanBailoutBottle> bailout,
  required DivePlanMode mode,
  required int gfLow,
  required int gfHigh,
  required bool useVpmb,
  required int vpmbConservatism,
  // MultiDeco / Petrel convention: bottom→first-stop walks at the
  // "Opgang" (transit / ascent) rate, between-stop and final-ascent
  // legs at the "Deco" rate. Defaults preserve the pre-split call-
  // site by tying both to ascentRateMpm.
  required int ascentRateMpm,
  int? ascentRateFastMpm,
  int? ascentRateSlowMpm,
  required int descentRateMpm,
  required double bottomSetpoint,
  required double ascentSetpoint,
  required double decoSetpoint,
  required double lastStopDepthMeters,
  required List<TankSpec> availableTanks,
}) {
  final fastMpm = ascentRateFastMpm ?? ascentRateMpm;
  final slowMpm = ascentRateSlowMpm ?? ascentRateMpm;
  // VPM-B forward-simulation is deferred (spec §9). The toggle is
  // accepted to keep the call-site stable; we always compute with
  // ZHL-16C until the existing vpmb.dart is verified to work outside
  // the replay engine.

  // Phase 1+2: walk the segments, get trigger tissues + summary stats.
  // Inter-segment ascents (multi-level: deeper → shallower) use the
  // FAST / "Opgang" rate — the diver is transiting, not decompressing.
  final sim = simulatePlan(
    gases: gases,
    segments: segments,
    mode: mode,
    descentRateMpm: descentRateMpm,
    ascentRateMpm: fastMpm,
    bottomSetpoint: bottomSetpoint,
    ascentSetpoint: ascentSetpoint,
    decoSetpoint: decoSetpoint,
  );

  // Phase 3: deco schedule from end-of-bottom tissues. For CCR the deco
  // is computed at the diver's deco-setpoint loop PPO2 (not the OC PPO2
  // of the diluent) — `planDeco`'s `setpointBar` plumbs that into the
  // inert-pp helper. lastStopDepthMeters extends the final hold so the
  // diver can surface from 6 m / 9 m instead of 3 m if they prefer.
  final diveGasMixes = gases.map(_toDiveGasMix).toList();
  final diveAscent = planDeco(
    initialN2Bar: sim.triggerN2Bar,
    initialHeBar: sim.triggerHeBar,
    triggerDepthMeters: sim.triggerDepthMeters,
    gases: diveGasMixes,
    gfLow: gfLow,
    gfHigh: gfHigh,
    ascentRateFastMPerMin: fastMpm,
    ascentRateSlowMPerMin: slowMpm,
    ppo2LimitBottom: 1.6,
    ppo2LimitDeco: 1.6,
    setpointBar: mode == DivePlanMode.cc ? decoSetpoint : 0.0,
    lastStopDepthMeters: lastStopDepthMeters,
  );

  // Convert DecoStep → AscentStop and stamp the setpoint used so the
  // output table can display it as the row's PPO2 (CC) without each
  // consumer reaching back into the planner config.
  final diveAscentStops = diveAscent
      .map((s) => AscentStop(
            depthStartMeters: s.depthStartMeters,
            depthEndMeters: s.depthEndMeters,
            duration: s.duration,
            gas: s.gas,
            volumeLitresConsumed: 0,
            setpointBar: mode == DivePlanMode.cc ? decoSetpoint : null,
          ))
      .toList();

  // Phase 4: bailout plan (Scenario A — user-supplied tanks).
  final userBailoutTanks = <DiveGasMix>[];
  final userTankVolumesL = <DiveGasMix, double>{};
  for (final bottle in bailout) {
    final mix = _toDiveGasMix(gases[bottle.gasMixIndex]);
    userBailoutTanks.add(mix);
    userTankVolumesL[mix] =
        (userTankVolumesL[mix] ?? 0) +
            bottle.waterCapacityL * bottle.fillPressureBar;
  }
  final bailoutResult = planBailout(
    diveId: 'plan-${DateTime.now().microsecondsSinceEpoch}',
    maxDepthMeters: sim.triggerDepthMeters,
    triggerDepthMeters: sim.triggerDepthMeters,
    recordedDiluent: gases.isEmpty ? null : _toDiveGasMix(gases.first),
    tissueN2Bar: sim.triggerN2Bar,
    tissueHeBar: sim.triggerHeBar,
    userBailoutTanks: userBailoutTanks,
    userTankVolumesL: userTankVolumesL,
    isGueConfig: false,
    gfLow: gfLow,
    gfHigh: gfHigh,
    sacBottom: 30,
    sacDeco: 20,
    ascentRateFast: ascentRateMpm,
    ascentRateSlow: ascentRateMpm,
    availableTanks: availableTanks,
  );

  // Phase 5: assemble — accumulate the ascent + deco phase into the
  // bottom-phase totals so the summary chips actually reflect the whole
  // dive (TTS = descent + bottom + deco-ascent, CNS / OTU likewise).
  Duration ascentDuration = Duration.zero;
  double ascentCns = 0;
  double ascentOtu = 0;
  for (final s in diveAscentStops) {
    ascentDuration += s.duration;
    final avgDepth = (s.depthStartMeters + s.depthEndMeters) / 2.0;
    final ambient = 1.013 + avgDepth / 10.0;
    final ppO2 = mode == DivePlanMode.cc
        ? (decoSetpoint > ambient ? ambient : decoSetpoint)
        : (s.gas.oxygenPercent / 100.0) * ambient;
    final minutes = s.duration.inSeconds / 60.0;
    // NOAA CNS table (matches plan_simulator's piecewise table).
    final cnsLimitMin = _noaaCnsLimitMinutes(ppO2);
    if (cnsLimitMin > 0) ascentCns += (minutes / cnsLimitMin) * 100.0;
    // Hamilton OTU formula.
    if (ppO2 > 0.5) {
      final base = (ppO2 - 0.5) / 0.5;
      ascentOtu += math.pow(base, 5.0 / 6.0).toDouble() * minutes;
    }
  }
  return PlanResult(
    profile: sim.profile,
    diveAscent: diveAscentStops,
    bailout: bailoutResult,
    cnsPercent: sim.cnsPercent + ascentCns,
    otuTotal: sim.otuTotal + ascentOtu,
    maxDensityGramsPerLitre: sim.maxDensityGramsPerLitre,
    totalRuntime: sim.totalRuntime + ascentDuration,
  );
}

DiveGasMix _toDiveGasMix(DivePlanGas g) => DiveGasMix(
      oxygenPercent: g.oxygenPercent,
      heliumPercent: g.heliumPercent,
      isDiluent: g.isDiluent,
    );

/// NOAA single-exposure CNS limit (minutes) at the given ppO2 (bar).
/// Same piecewise-linear table as [PlanSimulator] — duplicated here
/// because the simulator computes CNS during the bottom phase and the
/// runner has to accumulate the deco phase on top.
double _noaaCnsLimitMinutes(double ppO2) {
  if (ppO2 < 0.5) return 0;
  const points = <(double, double)>[
    (0.5, 720), (0.6, 720), (0.7, 570), (0.8, 450), (0.9, 360),
    (1.0, 300), (1.1, 240), (1.2, 210), (1.3, 180), (1.4, 150),
    (1.5, 120), (1.6, 45),
  ];
  if (ppO2 >= points.last.$1) return points.last.$2;
  for (var i = 0; i < points.length - 1; i++) {
    final a = points[i];
    final b = points[i + 1];
    if (ppO2 >= a.$1 && ppO2 < b.$1) {
      final f = (ppO2 - a.$1) / (b.$1 - a.$1);
      return a.$2 + (b.$2 - a.$2) * f;
    }
  }
  return points.first.$2;
}
