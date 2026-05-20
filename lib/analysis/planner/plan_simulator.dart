/// Forward-simulation of a dive plan: walks segments, advances the
/// existing tissue model minute-by-minute, returns trigger state +
/// summary stats. Feeds planDeco / planBailout downstream.
library;

import 'dart:math' as math;

import '../../data/models/dive.dart' show DiveGasMix;
import '../../data/models/dive_plan.dart';
import '../bailout/ascent_simulator.dart' show AscentStop;
import '../deco/schreiner.dart' show loadCompartment;
import '../deco/tissue_model.dart' show zhl16cTissues;
import '../loop_gas.dart' show loopGasAt;
import 'plan_result.dart';

const double _kSurfaceN2Bar =
    0.7902 * (1.013 - 0.0627); // alveolar water-vapour-corrected
const double _kSurfaceAtmBar = 1.013;

PlanSimulatorOutput simulatePlan({
  required List<DivePlanGas> gases,
  required List<DivePlanSegment> segments,
  required DivePlanMode mode,
  required int descentRateMpm,
  required int ascentRateMpm,
  required double bottomSetpoint,
  required double ascentSetpoint,
  required double decoSetpoint,
}) {
  final pN2 = List<double>.filled(16, _kSurfaceN2Bar);
  final pHe = List<double>.filled(16, 0.0);
  if (segments.isEmpty) {
    return PlanSimulatorOutput(
      triggerN2Bar: pN2,
      triggerHeBar: pHe,
      triggerDepthMeters: 0,
      totalRuntime: Duration.zero,
      cnsPercent: 0,
      otuTotal: 0,
      maxDensityGramsPerLitre: 0,
      profile: const [],
    );
  }

  double triggerDepth = 0;
  for (final s in segments) {
    if (s.durationMinutes > 0 && s.depthMeters > triggerDepth) {
      triggerDepth = s.depthMeters;
    }
  }

  // Accumulators.
  Duration totalTime = Duration.zero;
  double cnsAccum = 0;
  double otuAccum = 0;
  double maxDensity = 0;
  final profile = <AscentStop>[];

  // Active state — updated by time-0 segments.
  int activeGasIdx = segments.first.gasMixIndex;
  double activeSetpoint = segments.first.setpoint ?? bottomSetpoint;

  // ── Descent transit (surface → first segment depth) ──
  final firstSeg = segments.first;
  final descentSeconds =
      (firstSeg.depthMeters / descentRateMpm * 60).round();
  _advanceAndAccumulate(
    pN2: pN2,
    pHe: pHe,
    seconds: descentSeconds,
    avgDepthMeters: firstSeg.depthMeters / 2.0,
    mode: mode,
    gas: gases[activeGasIdx],
    setpoint: activeSetpoint,
    cnsOut: (delta) => cnsAccum += delta,
    otuOut: (delta) => otuAccum += delta,
    maxDensityOut: (d) => maxDensity = d > maxDensity ? d : maxDensity,
  );
  profile.add(AscentStop(
    depthStartMeters: 0,
    depthEndMeters: firstSeg.depthMeters,
    duration: Duration(seconds: descentSeconds),
    gas: _toDiveGasMix(gases[activeGasIdx]),
    volumeLitresConsumed: 0,
  ));
  totalTime += Duration(seconds: descentSeconds);

  double prevDepth = firstSeg.depthMeters;
  for (final seg in segments) {
    // Time-0 segments update active state without advancing time.
    if (seg.durationMinutes == 0) {
      activeGasIdx = seg.gasMixIndex;
      activeSetpoint = seg.setpoint ?? activeSetpoint;
      continue;
    }
    // Transit between depths (if needed) — uses descending or ascending
    // rate depending on direction.
    if (seg.depthMeters != prevDepth) {
      final delta = seg.depthMeters - prevDepth;
      final rate = delta > 0 ? descentRateMpm : ascentRateMpm;
      final transitSeconds = (delta.abs() / rate * 60).round();
      _advanceAndAccumulate(
        pN2: pN2,
        pHe: pHe,
        seconds: transitSeconds,
        avgDepthMeters: (seg.depthMeters + prevDepth) / 2.0,
        mode: mode,
        gas: gases[activeGasIdx],
        setpoint: activeSetpoint,
        cnsOut: (d) => cnsAccum += d,
        otuOut: (d) => otuAccum += d,
        maxDensityOut: (d) => maxDensity = d > maxDensity ? d : maxDensity,
      );
      profile.add(AscentStop(
        depthStartMeters: prevDepth,
        depthEndMeters: seg.depthMeters,
        duration: Duration(seconds: transitSeconds),
        gas: _toDiveGasMix(gases[activeGasIdx]),
        volumeLitresConsumed: 0,
      ));
      totalTime += Duration(seconds: transitSeconds);
    }
    // Apply gas / setpoint of the new segment from this point on.
    activeGasIdx = seg.gasMixIndex;
    activeSetpoint = seg.setpoint ?? activeSetpoint;
    // Level phase.
    _advanceAndAccumulate(
      pN2: pN2,
      pHe: pHe,
      seconds: seg.durationMinutes * 60,
      avgDepthMeters: seg.depthMeters,
      mode: mode,
      gas: gases[activeGasIdx],
      setpoint: activeSetpoint,
      cnsOut: (d) => cnsAccum += d,
      otuOut: (d) => otuAccum += d,
      maxDensityOut: (d) => maxDensity = d > maxDensity ? d : maxDensity,
    );
    profile.add(AscentStop(
      depthStartMeters: seg.depthMeters,
      depthEndMeters: seg.depthMeters,
      duration: Duration(minutes: seg.durationMinutes),
      gas: _toDiveGasMix(gases[activeGasIdx]),
      volumeLitresConsumed: 0,
    ));
    totalTime += Duration(minutes: seg.durationMinutes);
    prevDepth = seg.depthMeters;
  }

  return PlanSimulatorOutput(
    triggerN2Bar: pN2,
    triggerHeBar: pHe,
    triggerDepthMeters: triggerDepth,
    totalRuntime: totalTime,
    cnsPercent: cnsAccum,
    otuTotal: otuAccum,
    maxDensityGramsPerLitre: maxDensity,
    profile: profile,
  );
}

void _advanceAndAccumulate({
  required List<double> pN2,
  required List<double> pHe,
  required int seconds,
  required double avgDepthMeters,
  required DivePlanMode mode,
  required DivePlanGas gas,
  required double setpoint,
  required void Function(double) cnsOut,
  required void Function(double) otuOut,
  required void Function(double) maxDensityOut,
}) {
  if (seconds <= 0) return;
  final ambient = _kSurfaceAtmBar + avgDepthMeters / 10.0;

  // Compute inhaled inert pp values + ppO2 + density.
  late final double inhaledN2;
  late final double inhaledHe;
  late final double ppO2;
  late final double densityGl;
  if (mode == DivePlanMode.cc) {
    final loop = loopGasAt(
      depthMeters: avgDepthMeters,
      ppo2Bar: setpoint,
      diluent: _toDiveGasMix(gas),
    );
    inhaledN2 = loop.n2Fraction * ambient;
    inhaledHe = loop.heFraction * ambient;
    ppO2 = setpoint;
    densityGl = _density(loop.o2Fraction, loop.heFraction, ambient);
  } else {
    final fO2 = gas.oxygenPercent / 100.0;
    final fHe = gas.heliumPercent / 100.0;
    final fN2 = 1.0 - fO2 - fHe;
    inhaledN2 = fN2 * ambient;
    inhaledHe = fHe * ambient;
    ppO2 = fO2 * ambient;
    densityGl = _density(fO2, fHe, ambient);
  }
  if (densityGl > 0) maxDensityOut(densityGl);

  // Advance tissues.
  for (var c = 0; c < 16; c++) {
    pN2[c] = loadCompartment(
      currentLoadBar: pN2[c],
      inertGasPartialPressureBar: inhaledN2,
      halfTimeMin: zhl16cTissues[c].halfTimeN2Min,
      intervalSeconds: seconds,
    );
    pHe[c] = loadCompartment(
      currentLoadBar: pHe[c],
      inertGasPartialPressureBar: inhaledHe,
      halfTimeMin: zhl16cTissues[c].halfTimeHeMin,
      intervalSeconds: seconds,
    );
  }

  // NOAA CNS table (linear interpolation). Returns CNS-clock seconds per
  // breathing minute at ppO2. We approximate with a piecewise table.
  final cnsLimitMin = _noaaCnsLimitMinutes(ppO2);
  if (cnsLimitMin > 0) {
    final minutes = seconds / 60.0;
    cnsOut((minutes / cnsLimitMin) * 100.0);
  }

  // Hamilton OTU formula: OTU/min = ((ppO2 - 0.5) / 0.5)^(5/6) for ppO2 > 0.5.
  if (ppO2 > 0.5) {
    final minutes = seconds / 60.0;
    final otuRate = _hamiltonOtuPerMinute(ppO2);
    otuOut(otuRate * minutes);
  }
}

/// Gas density at ambient. ISA 15 °C: kO2=1.314, kN2=1.2013, kHe=0.166.
double _density(double fO2, double fHe, double ambientBar) {
  final fN2 = 1.0 - fO2 - fHe;
  final atOneAtm = fO2 * 1.314 + fN2 * 1.2013 + fHe * 0.166;
  return atOneAtm * ambientBar;
}

/// NOAA single-exposure CNS limit (minutes) at the given ppO2 (bar).
/// Linear interpolation between the published anchor points. Returns 0
/// when ppO2 < 0.5 (essentially no CNS clock).
double _noaaCnsLimitMinutes(double ppO2) {
  if (ppO2 < 0.5) return 0;
  // NOAA single-exposure 24-h limits.
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

double _hamiltonOtuPerMinute(double ppO2) {
  // OTU/min = ((ppO2 - 0.5) / 0.5)^(5/6) for ppO2 > 0.5.
  final base = (ppO2 - 0.5) / 0.5;
  if (base <= 0) return 0;
  return math.pow(base, 5.0 / 6.0).toDouble();
}

/// Bridges DivePlanGas → DiveGasMix for the existing loopGasAt helper.
DiveGasMix _toDiveGasMix(DivePlanGas g) => DiveGasMix(
      oxygenPercent: g.oxygenPercent,
      heliumPercent: g.heliumPercent,
      isDiluent: g.isDiluent,
    );
