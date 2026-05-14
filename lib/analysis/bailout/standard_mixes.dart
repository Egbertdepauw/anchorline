/// Standard mix tables for the bailout planner. Per Track D spec.
library;

import '../../data/models/dive.dart' show DiveGasMix;

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

const _ean50 = DiveGasMix(oxygenPercent: 50, heliumPercent: 0, isDiluent: false);
const _o2 = DiveGasMix(oxygenPercent: 100, heliumPercent: 0, isDiluent: false);

/// GUE bailout staging by trigger depth:
/// - ≤ 21 m   : no deco gases — bottom mix only (1 stage)
/// - 22–65 m  : add EAN 50 (2 stages)
/// - > 65 m   : add EAN 50 + O₂ (3 stages)
///
/// Per the GUE bailout convention: shallow dives carry the bottom mix
/// only, longer/deeper dives add EAN 50, and only the deeper-than-65 m
/// dives bring O₂ for the 6 m / 3 m stops.
List<DiveGasMix> gueDecoGasesForDepth(double maxDepthMeters) {
  if (maxDepthMeters > 65) return const [_ean50, _o2];
  if (maxDepthMeters > 21) return const [_ean50];
  return const [];
}

const double kPpo2MaxNonGue = 1.6;
const double kPpo2MaxGue = 1.0;
const double kEndMaxMetres = 39.0;
