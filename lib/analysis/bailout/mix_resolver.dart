/// Picks the appropriate bottom-mix gas for a bailout calculation.
/// Per Track D spec:
/// - If the dive's diluent is known, use it verbatim
/// - Otherwise compute optimal (O2, He) for the config's PPO2 target +
///   END ≤ 39m, then snap to the nearest standard mix that meets both
///   absolute safety constraints (PPO2 ≤ 1.6, END ≤ 39m)
library;

import '../../data/models/dive.dart' show DiveGasMix;
import 'standard_mixes.dart';

DiveGasMix resolveBottomMix({
  required DiveGasMix? recordedDiluent,
  required double maxDepthMeters,
  required bool isGueConfig,
}) {
  if (recordedDiluent != null) return recordedDiluent;

  final ppo2Target = isGueConfig ? kPpo2MaxGue : kPpo2MaxNonGue;
  final ambientBar = (maxDepthMeters + 10.0) / 10.0;
  final optO2 = ppo2Target / ambientBar;

  final candidates = isGueConfig ? kGueBottomMixes : kNonGueBottomMixes;
  DiveGasMix? best;
  double bestDelta = double.infinity;
  for (final mix in candidates) {
    final fO2 = mix.oxygenPercent / 100.0;
    final fHe = mix.heliumPercent / 100.0;
    final ppo2 = fO2 * ambientBar;
    final end = (maxDepthMeters + 10.0) * (1.0 - fHe) - 10.0;
    if (ppo2 > 1.6) continue;
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
