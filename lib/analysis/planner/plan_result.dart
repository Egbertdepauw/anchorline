/// Result types for the dive-plan computation pipeline.
library;

import '../../data/models/dive.dart' show DiveGasMix;
import '../bailout/ascent_simulator.dart' show AscentStop;
import '../bailout/bailout_result.dart' show BailoutResult;

/// Output of the full plan run (simulator + planDeco + planBailout).
class PlanResult {
  /// Descent + bottom + transit legs derived from the user's segments.
  /// Each leg is an [AscentStop] so the output table can render them
  /// uniformly alongside the deco ascent.
  final List<AscentStop> profile;

  /// Deco schedule from end-of-bottom to surface. Each leg carries the
  /// CCR setpoint the diver was on (null = OC).
  final List<AscentStop> diveAscent;

  /// OC bailout plan computed from end-of-bottom tissue state.
  final BailoutResult bailout;

  /// CNS % at end of dive (after deco).
  final double cnsPercent;

  /// OTU accumulated over the dive.
  final double otuTotal;

  /// Maximum gas density at depth (g/L).
  final double maxDensityGramsPerLitre;

  /// Total runtime: descent + bottom + ascent + deco.
  final Duration totalRuntime;

  /// Estimated O2 consumption over the dive (litres at 1 atm).
  ///
  /// For CCR this is the metabolic O2 the diver burns — independent of
  /// depth, ~1 L/min × runtime. For OC it's the diver's SAC × O2
  /// fraction × ambient pressure × time across every leg. Useful as a
  /// blending / oxygen-cylinder-capacity sanity check before the dive.
  final double oxygenConsumedLitres;

  /// Estimated total breathing-gas consumption (all gases combined) in
  /// litres at 1 atm. CCR: ~0 (loop is closed; the metabolic O2 share
  /// is broken out separately in [oxygenConsumedLitres]). OC: sum of
  /// SAC × ambient × duration across the descent + bottom + ascent
  /// phases. The OC chip in the output panel reads from this.
  final double gasConsumedLitres;

  /// Per-gas breakdown of [gasConsumedLitres] — keys are the gas
  /// mixes the diver breathed, values are litres-at-1-atm summed
  /// across all legs that used that mix. Ordered from highest
  /// consumption to lowest for direct rendering. The OC chip strip
  /// reads this to show "Tx18/45 3400 L · EAN50 980 L · …" instead
  /// of a single lumped number.
  final List<({DiveGasMix gas, double litres})> gasConsumedByMix;

  const PlanResult({
    required this.profile,
    required this.diveAscent,
    required this.bailout,
    required this.cnsPercent,
    required this.otuTotal,
    required this.maxDensityGramsPerLitre,
    required this.totalRuntime,
    required this.oxygenConsumedLitres,
    required this.gasConsumedLitres,
    required this.gasConsumedByMix,
  });
}

/// Intermediate output of [simulatePlan] — feeds planDeco + planBailout.
class PlanSimulatorOutput {
  final List<double> triggerN2Bar; // 16-element
  final List<double> triggerHeBar; // 16-element
  final double triggerDepthMeters;
  final Duration totalRuntime; // descent + bottom phase
  final double cnsPercent;
  final double otuTotal;
  final double maxDensityGramsPerLitre;

  /// Descent + bottom + transit legs the simulator walked, in order.
  /// Empty when no segments were supplied.
  final List<AscentStop> profile;

  const PlanSimulatorOutput({
    required this.triggerN2Bar,
    required this.triggerHeBar,
    required this.triggerDepthMeters,
    required this.totalRuntime,
    required this.cnsPercent,
    required this.otuTotal,
    required this.maxDensityGramsPerLitre,
    required this.profile,
  });
}
