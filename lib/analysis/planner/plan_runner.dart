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
  // Depth at/above which the loop switches from the ascent SP to the
  // deco SP. 0.0 (default) = always use deco SP on the ascent (legacy).
  double decoSwitchDepthMeters = 0.0,
  // Per-minute breathing rate for OC consumption math. CC plans burn
  // a small metabolic O2 share; OC plans burn ambient × sac × time.
  int ocSacLPerMin = 20,
}) {
  final fastMpm = ascentRateFastMpm ?? ascentRateMpm;
  final slowMpm = ascentRateSlowMpm ?? ascentRateMpm;
  // VPM-B forward-simulation is deferred (spec §9). The toggle is
  // accepted to keep the call-site stable; we always compute with
  // ZHL-16C until the existing vpmb.dart is verified to work outside
  // the replay engine.

  // Defence-in-depth against stale gas indices. The notifier now remaps
  // segment/bailout indices when a gas is deleted, but a draft saved
  // BEFORE that fix may still carry an out-of-range gasMixIndex. Clamp
  // every reference into the current gas list so a corrupt index
  // degrades to "wrong gas" instead of throwing RangeError and crashing
  // the whole plan screen. `gases` is guaranteed non-empty here (the
  // caller skips recompute when it's empty).
  final maxGasIdx = gases.length - 1;
  final segmentsSafe = segments
      .map((s) => s.gasMixIndex <= maxGasIdx && s.gasMixIndex >= 0
          ? s
          : DivePlanSegment(
              depthMeters: s.depthMeters,
              durationMinutes: s.durationMinutes,
              gasMixIndex: s.gasMixIndex.clamp(0, maxGasIdx),
              setpoint: s.setpoint))
      .toList();
  final bailoutSafe = bailout
      .map((b) => b.gasMixIndex <= maxGasIdx && b.gasMixIndex >= 0
          ? b
          : DivePlanBailoutBottle(
              gasMixIndex: b.gasMixIndex.clamp(0, maxGasIdx),
              waterCapacityL: b.waterCapacityL,
              fillPressureBar: b.fillPressureBar))
      .toList();

  // Phase 1+2: walk the segments, get trigger tissues + summary stats.
  // Inter-segment ascents (multi-level: deeper → shallower) use the
  // FAST / "Opgang" rate — the diver is transiting, not decompressing.
  final sim = simulatePlan(
    gases: gases,
    segments: segmentsSafe,
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
  //
  // CCR gas handling: planDeco's default behaviour is MultiDeco-style
  // "pick the richest safe gas at each stop", which auto-switches the
  // diluent at every standard switch depth. That's wrong on a CCR —
  // the diver doesn't swap diluent at 21 m just because EAN 50 is in
  // the gas list; they breathe the loop. We restrict planDeco to the
  // *single* gas active at the end of the segment walk so deco runs on
  // that diluent throughout. A diver who wants a mid-deco diluent
  // switch composes it with a 0-time segment in the segment list,
  // which moves the "active at end" gas to the desired mix.
  //
  // OC retains the original auto-select behaviour — that IS how OC
  // deco gas planning is supposed to work.
  final diveGasMixes = gases.map(_toDiveGasMix).toList();
  final List<DiveGasMix> decoGases;
  if (mode == DivePlanMode.cc && gases.isNotEmpty && segments.isNotEmpty) {
    var activeIdx = segments.first.gasMixIndex;
    for (final s in segments) {
      activeIdx = s.gasMixIndex;
    }
    final safeIdx = activeIdx < gases.length ? activeIdx : 0;
    decoGases = [diveGasMixes[safeIdx]];
  } else {
    decoGases = diveGasMixes;
  }
  // On CCR, the diver runs the bottom SP from leaving the bottom up to
  // the deco-switch depth, then switches to the higher deco SP for the
  // hyperoxic deco stops. A deep dive with bottom SP 1.3 and deco SP
  // 1.5 should keep 1.3 on the deep ascent leg (e.g. 74 m → 36 m) and
  // only show 1.5 at and below the switch depth. The "Ascent SP" is
  // the lower transit SP used during descent / inter-segment moves,
  // not the bottom→first-stop ascent.
  final diveAscent = planDeco(
    initialN2Bar: sim.triggerN2Bar,
    initialHeBar: sim.triggerHeBar,
    triggerDepthMeters: sim.triggerDepthMeters,
    gases: decoGases,
    gfLow: gfLow,
    gfHigh: gfHigh,
    ascentRateFastMPerMin: fastMpm,
    ascentRateSlowMPerMin: slowMpm,
    ppo2LimitBottom: 1.6,
    ppo2LimitDeco: 1.6,
    setpointBar: mode == DivePlanMode.cc ? decoSetpoint : 0.0,
    ascentSetpointBar:
        mode == DivePlanMode.cc && decoSwitchDepthMeters > 0
            ? bottomSetpoint
            : null,
    decoSwitchDepthMeters: decoSwitchDepthMeters,
    lastStopDepthMeters: lastStopDepthMeters,
  );

  // Convert DecoStep → AscentStop and stamp the setpoint used so the
  // output table can display it as the row's PPO2 (CC) without each
  // consumer reaching back into the planner config. The per-row
  // setpoint follows the same depth-switch rule the planner used —
  // a leg above the deco-switch depth runs on the bottom SP, a stop at
  // or below the switch depth runs on the deco SP. Volume = SAC ×
  // avg-ambient × minutes (OC) or metabolic O2 burn (CC).
  double rowSp(double avgDepthM) {
    if (mode != DivePlanMode.cc) return 0;
    final useBottom =
        decoSwitchDepthMeters > 0 && avgDepthM > decoSwitchDepthMeters;
    return useBottom ? bottomSetpoint : decoSetpoint;
  }

  double legVolumeLitres(double avgDepthM, Duration d) {
    final minutes = d.inSeconds / 60.0;
    if (mode == DivePlanMode.cc) {
      return _ccrMetabolicO2LPerMin * minutes;
    }
    final ambient = 1.013 + avgDepthM / 10.0;
    return ocSacLPerMin * ambient * minutes;
  }

  final diveAscentStops = diveAscent.map((s) {
    final avg = (s.depthStartMeters + s.depthEndMeters) / 2.0;
    return AscentStop(
      depthStartMeters: s.depthStartMeters,
      depthEndMeters: s.depthEndMeters,
      duration: s.duration,
      gas: s.gas,
      volumeLitresConsumed: legVolumeLitres(avg, s.duration),
      setpointBar: mode == DivePlanMode.cc ? rowSp(avg) : null,
    );
  }).toList();

  // Stamp volumes on the simulator's bottom-phase profile too. The
  // simulator returns legs without consumption — fill them in here so
  // the VOL column reads non-zero across the whole dive.
  final simProfile = sim.profile.map((s) {
    final avg = (s.depthStartMeters + s.depthEndMeters) / 2.0;
    return AscentStop(
      depthStartMeters: s.depthStartMeters,
      depthEndMeters: s.depthEndMeters,
      duration: s.duration,
      gas: s.gas,
      volumeLitresConsumed: legVolumeLitres(avg, s.duration),
      setpointBar: s.setpointBar,
    );
  }).toList();

  // Phase 4: bailout plan (Scenario A — user-supplied tanks).
  final userBailoutTanks = <DiveGasMix>[];
  final userTankVolumesL = <DiveGasMix, double>{};
  for (final bottle in bailoutSafe) {
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
  final totalRuntime = sim.totalRuntime + ascentDuration;
  final oxygenConsumedLitres = _estimateOxygenConsumed(
    mode: mode,
    profile: simProfile,
    diveAscent: diveAscentStops,
    decoSetpoint: decoSetpoint,
    totalRuntime: totalRuntime,
    ocSacLPerMin: ocSacLPerMin,
  );
  // Total OC gas litres = sum of per-leg volumeLitresConsumed across
  // profile + diveAscent. On CC mode each leg's stamped volume is the
  // tiny metabolic O2 burn (≈ runtime × 1 L/min), so this stays near
  // oxygenConsumedLitres — the OC chip checks mode and hides itself
  // when CC, so the small number isn't misleading. OC mode: this is
  // the headline number for cylinder-capacity sanity.
  //
  // Per-gas breakdown: sum each gas's contribution separately so the
  // OC chip strip can render "Tx18/45 3400 L · EAN50 980 L" instead of
  // one lumped number.
  double gasConsumedLitres = 0;
  final perGasLitres = <DiveGasMix, double>{};
  void tallyLeg(AscentStop s) {
    gasConsumedLitres += s.volumeLitresConsumed;
    if (s.volumeLitresConsumed <= 0) return;
    perGasLitres.update(
      s.gas,
      (existing) => existing + s.volumeLitresConsumed,
      ifAbsent: () => s.volumeLitresConsumed,
    );
  }

  for (final s in simProfile) {
    tallyLeg(s);
  }
  for (final s in diveAscentStops) {
    tallyLeg(s);
  }
  final gasConsumedByMix = perGasLitres.entries
      .map((e) => (gas: e.key, litres: e.value))
      .toList()
    ..sort((a, b) => b.litres.compareTo(a.litres));

  return PlanResult(
    profile: simProfile,
    diveAscent: diveAscentStops,
    bailout: bailoutResult,
    cnsPercent: sim.cnsPercent + ascentCns,
    otuTotal: sim.otuTotal + ascentOtu,
    maxDensityGramsPerLitre: sim.maxDensityGramsPerLitre,
    totalRuntime: totalRuntime,
    oxygenConsumedLitres: oxygenConsumedLitres,
    gasConsumedLitres: gasConsumedLitres,
    gasConsumedByMix: gasConsumedByMix,
  );
}

/// Standard metabolic O2 burn for an adult diver under load. Used as
/// the CCR estimate — the loop is closed, so the only O2 leaving the
/// system is what the diver metabolises (plus any vented gas, which a
/// well-tuned CCR keeps near zero).
const double _ccrMetabolicO2LPerMin = 1.0;

/// Estimates litres of O2 consumed over the planned dive.
///
/// CCR: metabolic rate × runtime — depth-independent.
///
/// OC: each leg uses fO2 × ambient × SAC × duration, where SAC comes
/// from the caller (defaults to 20 L/min if omitted).
double _estimateOxygenConsumed({
  required DivePlanMode mode,
  required List<AscentStop> profile,
  required List<AscentStop> diveAscent,
  required double decoSetpoint,
  required Duration totalRuntime,
  int ocSacLPerMin = 20,
}) {
  if (mode == DivePlanMode.cc) {
    return _ccrMetabolicO2LPerMin * (totalRuntime.inSeconds / 60.0);
  }
  // OC — sum the per-leg consumption.
  final sacLPerMin = ocSacLPerMin.toDouble();
  double total = 0;
  void accumulate(List<AscentStop> legs) {
    for (final s in legs) {
      final avgDepth = (s.depthStartMeters + s.depthEndMeters) / 2.0;
      final ambient = 1.013 + avgDepth / 10.0;
      final fO2 = s.gas.oxygenPercent / 100.0;
      final minutes = s.duration.inSeconds / 60.0;
      total += sacLPerMin * ambient * fO2 * minutes;
    }
  }

  accumulate(profile);
  accumulate(diveAscent);
  return total;
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
