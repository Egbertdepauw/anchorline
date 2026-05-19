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
const _tx2135 =
    DiveGasMix(oxygenPercent: 21, heliumPercent: 35, isDiluent: false);
const _tx3525 =
    DiveGasMix(oxygenPercent: 35, heliumPercent: 25, isDiluent: false);

/// GUE bailout staging by trigger depth:
/// - ≤ 21 m    : no deco gases — bottom mix only (1 stage)
/// - 22–65 m   : add EAN 50 (2 stages: bottom + EAN50)
/// - 66–100 m  : add TX 21/35, EAN 50, O₂  (4 stages: bottom + 3)
/// - > 100 m   : add TX 21/35, TX 35/25, EAN 50, O₂  (5 stages:
///   bottom + 4 — the extra TX 35/25 intermediate keeps the bottom-
///   mix-volume from blowing up on really deep ascents)
///
/// Why the intermediate trimixes on deeper dives: a bailout from say
/// 145 m on TX 10/70 would otherwise have to breathe the helium-rich
/// bottom mix all the way from 145 m to the EAN 50 switch at 21 m,
/// consuming 5000+ litres of bottom mix and forcing 2× bottom-stage
/// redundancy. Adding TX 21/35 as a travel/intermediate gas at its
/// 57 m switch depth drops the bottom-mix-volume by ~75 % and keeps
/// the stage count practical. TX 35/25 (switch 36 m) covers the
/// shallower portion of the same ascent.
List<DiveGasMix> gueDecoGasesForDepth(double maxDepthMeters) {
  if (maxDepthMeters > 100) {
    return const [_tx2135, _tx3525, _ean50, _o2];
  }
  if (maxDepthMeters > 65) return const [_tx2135, _ean50, _o2];
  if (maxDepthMeters > 21) return const [_ean50];
  return const [];
}

const double kPpo2MaxNonGue = 1.6;
const double kPpo2MaxGue = 1.0;
const double kEndMaxMetres = 39.0;
