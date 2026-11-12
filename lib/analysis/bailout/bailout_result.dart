/// Result types for the bailout planner.
///
/// [BailoutResult] is the single value returned by [planBailout].  It carries
/// the full ascent plan plus per-gas usage and a human-readable verdict.
library;

import 'package:subsurface_core/data/models/dive.dart' show DiveGasMix;
import 'ascent_simulator.dart' show AscentStop;
import 'tank_recommender.dart' show TankRecommendation;

/// Which planning mode was used.
enum BailoutScenario {
  /// User supplied explicit bailout tanks (Scenario A).
  tanksDefined,

  /// No user tanks supplied; planner selects tanks from the catalogue
  /// using standard mixes (Scenario B).
  standardGases,
}

/// Overall verdict for the bailout plan.
enum BailoutVerdict {
  /// All required gas volumes can be satisfied.
  sufficient,

  /// At least one gas has a shortfall, but at least one gas is fine.
  partialShortfall,

  /// A critical gas (or all gases in Scenario B) cannot be covered.
  insufficient,
}

/// Per-gas volume accounting.
class GasUsage {
  /// Total gas required for the ascent (L, at surface pressure).
  final double requiredL;

  /// Total gas available (L).  Null in Scenario B where tanks are
  /// being recommended rather than evaluated.
  final double? availableL;

  /// Tank recommendation produced for Scenario B.  Null in Scenario A.
  final TankRecommendation? recommendedTank;

  const GasUsage({
    required this.requiredL,
    this.availableL,
    this.recommendedTank,
  });
}

/// The complete output of [planBailout].
class BailoutResult {
  /// Which scenario was detected.
  final BailoutScenario scenario;

  /// Total ascent time (all stops + travel legs).
  final Duration totalTime;

  /// Ordered list of ascent legs / deco stops from the simulator.
  final List<AscentStop> stops;

  /// Gas volume accounting keyed by mix.
  final Map<DiveGasMix, GasUsage> perGas;

  /// Overall verdict.
  final BailoutVerdict verdict;

  /// One human-readable line per gas summarising the verdict.
  final List<String> verdictDetails;

  const BailoutResult({
    required this.scenario,
    required this.totalTime,
    required this.stops,
    required this.perGas,
    required this.verdict,
    required this.verdictDetails,
  });
}
