/// Forward-simulation of a dive plan: walks segments, advances the
/// existing tissue model minute-by-minute, returns trigger state +
/// summary stats. Feeds planDeco / planBailout downstream.
///
/// Scope of this file (Task 6): square CC dives — descent to first
/// segment, level at that depth for its duration. Time-0 segments
/// (gas / setpoint switches) and CNS/OTU/density accumulators land
/// in later tasks; their fields are present on the output type but
/// computed as zero here.
library;

import '../../data/models/dive.dart' show DiveGasMix;
import '../../data/models/dive_plan.dart';
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
  // Initialise tissues to surface equilibrium (N2 only).
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
    );
  }

  // Determine trigger depth: deepest segment with time > 0.
  double triggerDepth = 0;
  for (final s in segments) {
    if (s.durationMinutes > 0 && s.depthMeters > triggerDepth) {
      triggerDepth = s.depthMeters;
    }
  }

  // ── Descent transit: surface → segment 0 at descent rate ──
  final firstSeg = segments.first;
  final descentSeconds =
      (firstSeg.depthMeters / descentRateMpm * 60).round();
  _advanceTissuesOverInterval(
    pN2: pN2,
    pHe: pHe,
    seconds: descentSeconds,
    avgDepthMeters: firstSeg.depthMeters / 2.0,
    mode: mode,
    gas: gases[firstSeg.gasMixIndex],
    setpoint: firstSeg.setpoint ?? bottomSetpoint,
  );

  // ── Walk segments ──
  Duration totalTime = Duration(seconds: descentSeconds);
  double prevDepth = firstSeg.depthMeters;
  for (final seg in segments) {
    // Transit from prevDepth to seg.depth if they differ.
    if (seg.depthMeters != prevDepth && seg.durationMinutes > 0) {
      final delta = seg.depthMeters - prevDepth;
      final rate = delta > 0 ? descentRateMpm : ascentRateMpm;
      final transitSeconds = (delta.abs() / rate * 60).round();
      _advanceTissuesOverInterval(
        pN2: pN2,
        pHe: pHe,
        seconds: transitSeconds,
        avgDepthMeters: (seg.depthMeters + prevDepth) / 2.0,
        mode: mode,
        gas: gases[seg.gasMixIndex],
        setpoint: seg.setpoint ?? bottomSetpoint,
      );
      totalTime += Duration(seconds: transitSeconds);
    }
    // Level segment at constant depth.
    if (seg.durationMinutes > 0) {
      _advanceTissuesOverInterval(
        pN2: pN2,
        pHe: pHe,
        seconds: seg.durationMinutes * 60,
        avgDepthMeters: seg.depthMeters,
        mode: mode,
        gas: gases[seg.gasMixIndex],
        setpoint: seg.setpoint ?? bottomSetpoint,
      );
      totalTime += Duration(minutes: seg.durationMinutes);
      prevDepth = seg.depthMeters;
    }
  }

  return PlanSimulatorOutput(
    triggerN2Bar: pN2,
    triggerHeBar: pHe,
    triggerDepthMeters: triggerDepth,
    totalRuntime: totalTime,
    cnsPercent: 0, // computed in Task 7
    otuTotal: 0,
    maxDensityGramsPerLitre: 0,
  );
}

/// Advances every compartment for [seconds] at constant ambient given
/// by [avgDepthMeters]. The inhaled inert-gas pp values come from
/// [gas] + [setpoint] (CC) or [gas] alone (OC).
void _advanceTissuesOverInterval({
  required List<double> pN2,
  required List<double> pHe,
  required int seconds,
  required double avgDepthMeters,
  required DivePlanMode mode,
  required DivePlanGas gas,
  required double setpoint,
}) {
  if (seconds <= 0) return;
  final ambient = _kSurfaceAtmBar + avgDepthMeters / 10.0;
  late final double inhaledN2;
  late final double inhaledHe;
  if (mode == DivePlanMode.cc) {
    final loop = loopGasAt(
      depthMeters: avgDepthMeters,
      ppo2Bar: setpoint,
      diluent: _toDiveGasMix(gas),
    );
    inhaledN2 = loop.n2Fraction * ambient;
    inhaledHe = loop.heFraction * ambient;
  } else {
    final fO2 = gas.oxygenPercent / 100.0;
    final fHe = gas.heliumPercent / 100.0;
    final fN2 = 1.0 - fO2 - fHe;
    inhaledN2 = fN2 * ambient;
    inhaledHe = fHe * ambient;
  }
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
}

/// Bridges DivePlanGas → DiveGasMix for the existing loopGasAt helper.
DiveGasMix _toDiveGasMix(DivePlanGas g) => DiveGasMix(
      oxygenPercent: g.oxygenPercent,
      heliumPercent: g.heliumPercent,
      isDiluent: g.isDiluent,
    );
