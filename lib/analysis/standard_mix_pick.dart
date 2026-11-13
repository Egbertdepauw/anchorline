/// Picks the nearest standard gas mix for an analysed reading, and decides
/// a gas role.
///
/// Pure Dart, no Flutter imports. Cylinder labels print the desired mix's
/// name, so an automatic pick only happens when it grades [MixMatchLevel.match]
/// or [MixMatchLevel.orange] (see `gradeMix`), never red or hard.
library;

import '../data/models/gas_analysis.dart';
import 'mix_match.dart';

/// The standard mixes an analysis may snap to, in display order.
const List<DesiredMix> kStandardMixes = [
  DesiredMix(21, 0), // Air
  DesiredMix(32, 0), // EAN32
  DesiredMix(50, 0), // EAN50
  DesiredMix(100, 0), // O2
  DesiredMix(30, 30),
  DesiredMix(21, 35),
  DesiredMix(18, 45),
  DesiredMix(15, 55),
  DesiredMix(12, 65),
  DesiredMix(10, 70),
  DesiredMix(35, 25),
];

/// Where a [MixPick] came from.
/// [blendTarget] means the target of an open blend (the name predates open
/// blends, when it was the Blend tab's single target).
enum MixPickSource { blendTarget, standard }

typedef MixPick = ({
  DesiredMix mix,
  MixPickSource source,
  MixMatchLevel level,
});

/// The desired mix for a reading: the [blendTarget] when it grades match or
/// orange, otherwise the best standard mix that does. Null when nothing is
/// within orange.
///
/// Among standard mixes, match beats orange, then the smaller O2 difference,
/// then the smaller He difference.
MixPick? pickDesiredMix({
  required double o2Percent,
  required double hePercent,
  // An open blend's target (the name is from the old single Blend target).
  DesiredMix? blendTarget,
}) {
  MixMatch grade(DesiredMix m) => gradeMix(
        o2Percent: o2Percent,
        hePercent: hePercent,
        targetO2Percent: m.o2Percent,
        targetHePercent: m.hePercent,
      );
  bool usable(MixMatch g) =>
      g.level == MixMatchLevel.match || g.level == MixMatchLevel.orange;

  if (blendTarget != null) {
    final g = grade(blendTarget);
    if (usable(g)) {
      return (
        mix: blendTarget,
        source: MixPickSource.blendTarget,
        level: g.level,
      );
    }
  }

  DesiredMix? best;
  MixMatch? bestGrade;
  for (final m in kStandardMixes) {
    final g = grade(m);
    if (!usable(g)) continue;
    if (bestGrade == null || _better(g, bestGrade)) {
      best = m;
      bestGrade = g;
    }
  }
  if (best == null || bestGrade == null) return null;
  return (mix: best, source: MixPickSource.standard, level: bestGrade.level);
}

bool _better(MixMatch a, MixMatch b) {
  if (a.level != b.level) return a.level.index < b.level.index;
  if (a.o2Off != b.o2Off) return a.o2Off < b.o2Off;
  return a.heOff < b.heOff;
}

/// Above this O2 percentage a mix is bailout/deco rather than diluent.
const double kBailoutRoleAboveO2Percent = 30;

/// The role a mix implies when nothing else says: lean mixes are diluent.
GasRole gasRoleForMix(double o2Percent) =>
    o2Percent > kBailoutRoleAboveO2Percent ? GasRole.bailout : GasRole.diluent;

/// A tapped role wins, then the role of the open blend being closed, then
/// the cylinder's role, then the mix.
GasRole resolveGasRole({
  GasRole? tapped,
  GasRole? blendRole,
  String? cylinderRole,
  required double o2PercentForRule,
}) {
  if (tapped != null) return tapped;
  if (blendRole != null) return blendRole;
  if (cylinderRole != null) return gasRoleForCylinderRole(cylinderRole);
  return gasRoleForMix(o2PercentForRule);
}
