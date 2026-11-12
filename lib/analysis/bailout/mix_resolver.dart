/// Picks the appropriate bottom-mix gas for a bailout calculation.
/// Per Track D spec:
/// - If the dive's diluent is known AND safe at [maxDepthMeters] (PPO2
///   ≤ 1.6), use it verbatim — it's already what the diver's been
///   breathing.
/// - Otherwise compute optimal (O2, He) for the config's PPO2 target +
///   END ≤ 39m, then snap to the nearest standard mix that meets both
///   absolute safety constraints (PPO2 ≤ 1.6, END ≤ 39m).
///
/// The depth-safety check on the recorded diluent matters: a CCR diluent
/// can be richer than what's breathable OC at depth (e.g. EAN 50 used as
/// a "diluent" on a shallow-CCR setup, or a misflagged import). Without
/// the gate, the planner inherits an unbreathable bottom mix and falls
/// back to "first gas in the list" — which silently yields a deco-gas
/// plan starting at depth.
library;

import 'package:subsurface_core/data/models/dive.dart' show DiveGasMix;
import 'standard_mixes.dart';

/// Hard PPO2 cap for selecting / accepting a bottom mix at [maxDepthMeters].
/// Per the user's convention: ≤ 65 m → 1.6 bar, > 65 m → 1.5 bar (the
/// deeper window narrows the working PPO2 so the bottom mix stays
/// breathable on the very deepest moment of the dive).
double bottomPpo2Limit(double maxDepthMeters) =>
    maxDepthMeters > 65 ? 1.5 : 1.6;

DiveGasMix resolveBottomMix({
  required DiveGasMix? recordedDiluent,
  required double maxDepthMeters,
  required bool bailoutCapableDiluent,
}) {
  final ambientBar = (maxDepthMeters + 10.0) / 10.0;
  final ppo2Limit = bottomPpo2Limit(maxDepthMeters);

  if (recordedDiluent != null) {
    final ppo2 = (recordedDiluent.oxygenPercent / 100.0) * ambientBar;
    final fHe = recordedDiluent.heliumPercent / 100.0;
    final end = (maxDepthMeters + 10.0) * (1.0 - fHe) - 10.0;
    // Use the diluent verbatim only when it's breathable AND narcotic
    // enough at the deepest point.
    if (ppo2 <= ppo2Limit && end <= kEndMaxMetres) return recordedDiluent;
    // Otherwise fall through to the snap.
  }

  final ppo2Target = bailoutCapableDiluent ? kPpo2MaxBailoutDiluent : kPpo2MaxBottomMix;
  final optO2 = ppo2Target / ambientBar;

  final candidates = bailoutCapableDiluent ? kBailoutDiluentBottomMixes : kBottomMixes;
  DiveGasMix? best;
  double bestDelta = double.infinity;
  for (final mix in candidates) {
    final fO2 = mix.oxygenPercent / 100.0;
    final fHe = mix.heliumPercent / 100.0;
    final ppo2 = fO2 * ambientBar;
    final end = (maxDepthMeters + 10.0) * (1.0 - fHe) - 10.0;
    if (ppo2 > ppo2Limit) continue;
    if (end > kEndMaxMetres) continue;
    final delta = (fO2 - optO2).abs();
    if (delta < bestDelta) {
      best = mix;
      bestDelta = delta;
    }
  }
  best ??= candidates.last;
  return best;
}
