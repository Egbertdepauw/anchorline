/// Result types for the dive-plan computation pipeline.
library;

import '../bailout/ascent_simulator.dart' show AscentStop;
import '../bailout/bailout_result.dart' show BailoutResult;
import '../deco/deco_step.dart' show DecoStep;

/// Output of the full plan run (simulator + planDeco + planBailout).
class PlanResult {
  /// Descent + bottom + transit legs derived from the user's segments.
  /// Each leg is an [AscentStop] so the output table can render them
  /// uniformly alongside the deco ascent.
  final List<AscentStop> profile;

  /// Deco schedule from end-of-bottom to surface.
  final List<DecoStep> diveAscent;

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

  const PlanResult({
    required this.profile,
    required this.diveAscent,
    required this.bailout,
    required this.cnsPercent,
    required this.otuTotal,
    required this.maxDensityGramsPerLitre,
    required this.totalRuntime,
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
