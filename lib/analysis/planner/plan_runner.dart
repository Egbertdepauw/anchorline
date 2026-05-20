/// Orchestrates the full plan computation:
///   simulator → trigger tissues → planDeco → planBailout → PlanResult.
library;

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
  required int ascentRateMpm,
  required int descentRateMpm,
  required double bottomSetpoint,
  required double ascentSetpoint,
  required double decoSetpoint,
  required double lastStopDepthMeters,
  required List<TankSpec> availableTanks,
}) {
  // VPM-B forward-simulation is deferred (spec §9). The toggle is
  // accepted to keep the call-site stable; we always compute with
  // ZHL-16C until the existing vpmb.dart is verified to work outside
  // the replay engine.

  // Phase 1+2: walk the segments, get trigger tissues + summary stats.
  final sim = simulatePlan(
    gases: gases,
    segments: segments,
    mode: mode,
    descentRateMpm: descentRateMpm,
    ascentRateMpm: ascentRateMpm,
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
    ascentRateFastMPerMin: ascentRateMpm,
    ascentRateSlowMPerMin: ascentRateMpm,
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

  // Phase 5: assemble.
  return PlanResult(
    profile: sim.profile,
    diveAscent: diveAscentStops,
    bailout: bailoutResult,
    cnsPercent: sim.cnsPercent,
    otuTotal: sim.otuTotal,
    maxDensityGramsPerLitre: sim.maxDensityGramsPerLitre,
    totalRuntime: sim.totalRuntime,
  );
}

DiveGasMix _toDiveGasMix(DivePlanGas g) => DiveGasMix(
      oxygenPercent: g.oxygenPercent,
      heliumPercent: g.heliumPercent,
      isDiluent: g.isDiluent,
    );
