/// Standard mix tables for the bailout planner. Per Track D spec.
library;

import 'package:subsurface_core/data/models/dive.dart' show DiveGasMix;

const List<DiveGasMix> kNonGueBottomMixes = [
  DiveGasMix(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
  DiveGasMix(oxygenPercent: 18, heliumPercent: 45, isDiluent: true),
  DiveGasMix(oxygenPercent: 15, heliumPercent: 55, isDiluent: true),
  DiveGasMix(oxygenPercent: 12, heliumPercent: 65, isDiluent: true),
  DiveGasMix(oxygenPercent: 10, heliumPercent: 70, isDiluent: true),
];

const List<DiveGasMix> kGueBottomMixes = [
  DiveGasMix(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
  DiveGasMix(oxygenPercent: 18, heliumPercent: 45, isDiluent: true),
  DiveGasMix(oxygenPercent: 15, heliumPercent: 55, isDiluent: true),
];

/// Non-GUE deco gases: full ladder including EAN 32 for shallow/short
/// deco. Used as the deco list when [gueDiluentConfig] is OFF.
const List<DiveGasMix> kDecoMixes = [
  DiveGasMix(oxygenPercent: 32, heliumPercent: 0, isDiluent: false),
  DiveGasMix(oxygenPercent: 50, heliumPercent: 0, isDiluent: false),
  DiveGasMix(oxygenPercent: 100, heliumPercent: 0, isDiluent: false),
];

const kEan50 = DiveGasMix(oxygenPercent: 50, heliumPercent: 0, isDiluent: false);
const kO2 = DiveGasMix(oxygenPercent: 100, heliumPercent: 0, isDiluent: false);
const kTx2135 =
    DiveGasMix(oxygenPercent: 21, heliumPercent: 35, isDiluent: false);
const kTx3525 =
    DiveGasMix(oxygenPercent: 35, heliumPercent: 25, isDiluent: false);

/// Minimum GUE-flavoured deco-gas ladder by max depth. The planner starts
/// from this list and escalates volume-by-volume — inserting TX 21/35
/// (57 m switch) and TX 35/25 (36 m switch) only when bottom-mix volume
/// would overflow the largest tank in the user's catalogue. The goal is
/// the fewest stages that still fit in normal tanks (AL80 / 12L@300).
///
/// - ≤ 21 m   : bottom only (1 stage)
/// - 22–65 m  : bottom + EAN 50 (2 stages)
/// - > 65 m   : bottom + EAN 50 + O₂ (3 stages baseline)
///
/// Intermediates are not on this list — they're a planner concern (see
/// `bailout_planner.dart`'s escalation loop).
List<DiveGasMix> gueDecoGasesForDepth(double maxDepthMeters) {
  if (maxDepthMeters > 65) return const [kEan50, kO2];
  if (maxDepthMeters > 21) return const [kEan50];
  return const [];
}

const double kPpo2MaxNonGue = 1.6;
const double kPpo2MaxGue = 1.0;
const double kEndMaxMetres = 39.0;
