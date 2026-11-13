/// Matching an analysis to an open blend, the settle colour, the role guess
/// and the mix warning (issue #112).
///
/// Pure Dart, no Flutter imports.
library;

import '../data/models/gas_analysis.dart';
import '../data/models/open_blend.dart';
import '../labels/cylinder_label.dart';
import 'gas_naming.dart';
import 'mix_match.dart';

typedef RankedBlend = ({OpenBlend blend, MixMatch grade});

/// Every open blend graded against the reading, best first: grade level,
/// then O2 difference, then He difference, then oldest blend first.
List<RankedBlend> rankOpenBlends({
  required double o2Percent,
  required double hePercent,
  required List<OpenBlend> open,
}) {
  final ranked = [
    for (final b in open)
      (
        blend: b,
        grade: gradeMix(
          o2Percent: o2Percent,
          hePercent: hePercent,
          targetO2Percent: b.target.o2Percent,
          targetHePercent: b.target.hePercent,
        ),
      ),
  ];
  ranked.sort((a, b) {
    final level = a.grade.level.index.compareTo(b.grade.level.index);
    if (level != 0) return level;
    final o2 = a.grade.o2Off.compareTo(b.grade.o2Off);
    if (o2 != 0) return o2;
    final he = a.grade.heOff.compareTo(b.grade.heOff);
    if (he != 0) return he;
    return a.blend.blendedAt.compareTo(b.blend.blendedAt);
  });
  return ranked;
}

/// What the diver chose for the blend an analysis closes.
sealed class BlendChoice {
  const BlendChoice();
}

/// Let the app match it.
final class AutoBlend extends BlendChoice {
  const AutoBlend();
}

/// Close no blend.
final class NoBlend extends BlendChoice {
  const NoBlend();
}

/// Close this blend, whatever it grades.
final class PickedBlend extends BlendChoice {
  final OpenBlend blend;
  const PickedBlend(this.blend);
}

/// The blend an analysis closes, or null.
OpenBlend? blendForAnalysis({
  required double o2Percent,
  required double hePercent,
  required BlendChoice choice,
  DesiredMix? chosenMix,
  required bool residual,
  required List<OpenBlend> open,
}) {
  if (residual) return null;
  switch (choice) {
    case PickedBlend(:final blend):
      return blend;
    case NoBlend():
      return null;
    case AutoBlend():
      if (chosenMix != null) {
        OpenBlend? oldest;
        for (final b in open) {
          if (b.target != chosenMix) continue;
          if (oldest == null || b.blendedAt.isBefore(oldest.blendedAt)) {
            oldest = b;
          }
        }
        return oldest;
      }
      final ranked = rankOpenBlends(
          o2Percent: o2Percent, hePercent: hePercent, open: open);
      if (ranked.isEmpty) return null;
      final level = ranked.first.grade.level;
      return level == MixMatchLevel.match || level == MixMatchLevel.orange
          ? ranked.first.blend
          : null;
  }
}

/// The nearest open blend when it grades red or hard, for "nearest is ...".
RankedBlend? nearestUnmatched({
  required double o2Percent,
  required double hePercent,
  required List<OpenBlend> open,
}) {
  final ranked =
      rankOpenBlends(o2Percent: o2Percent, hePercent: hePercent, open: open);
  if (ranked.isEmpty) return null;
  final level = ranked.first.grade.level;
  return level == MixMatchLevel.red || level == MixMatchLevel.hard
      ? ranked.first
      : null;
}

/// How settled a blend is: red under half the settle time, orange under the
/// full time, green after. A settle time of 0 is always green; a negative
/// elapsed time (a clock that moved back) is red.
enum SettleState { red, orange, green }

SettleState settleState({
  required Duration sinceBlended,
  required int settleMinutes,
}) {
  if (sinceBlended.isNegative) return SettleState.red;
  if (settleMinutes <= 0) return SettleState.green;
  final full = Duration(minutes: settleMinutes);
  if (sinceBlended >= full) return SettleState.green;
  return sinceBlended * 2 >= full ? SettleState.orange : SettleState.red;
}

typedef RoleGuess = ({GasRole role, String reason});

/// Above this O2 percentage a blend is bailout, not diluent.
const int kBlendBailoutAboveO2Percent = 32;

/// A role from the blend's target O2 and cylinder size.
RoleGuess guessBlendRole({
  required int targetO2Percent,
  required double waterCapacityL,
  required double diluentMaxL,
}) {
  if (targetO2Percent > kBlendBailoutAboveO2Percent) {
    return (role: GasRole.bailout, reason: 'O2 above 32%');
  }
  final cap = waterCapacityL.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  return (
    role: waterCapacityL <= diluentMaxL ? GasRole.diluent : GasRole.bailout,
    reason: '$cap L',
  );
}

enum WarningLevel { mild, loud }

typedef MixWarning = ({WarningLevel level, String text});

/// A warning for an analysis that is off its blend's target; null for a
/// match. Loud when a non-diluent gas has MORE O2 than planned, since its
/// real MOD is shallower than the planned one.
MixWarning? mixWarning({
  required GasRole role,
  required double o2Percent,
  required double hePercent,
  required DesiredMix target,
  required bool use14ForDeeperMixes,
}) {
  final g = gradeMix(
    o2Percent: o2Percent,
    hePercent: hePercent,
    targetO2Percent: target.o2Percent,
    targetHePercent: target.hePercent,
  );
  if (g.level == MixMatchLevel.match) return null;
  if (!role.isDiluent &&
      g.o2Off > kO2MatchMax &&
      o2Percent > target.o2Percent) {
    // Same ppO2 and depth rule as the cylinder label (CylinderLabel
    // .fromAnalysis): a hard mismatch is judged on the analysed gas.
    final hard = g.level == MixMatchLevel.hard;
    final ppo2 = bailoutModPpo2(
      o2PercentForRule: hard ? o2Percent.round() : target.o2Percent,
      use14ForDeeperMixes: use14ForDeeperMixes,
    );
    final actual = limitDepthMeters(o2Percent, ppo2,
        desiredO2Percent: hard ? null : target.o2Percent);
    final planned = limitDepthMeters(target.o2Percent.toDouble(), ppo2);
    return (
      level: WarningLevel.loud,
      text: 'O2 ${o2Percent.toStringAsFixed(1)}% instead of '
          '${target.o2Percent}%: MOD at ${ppo2.toStringAsFixed(1)} is '
          '${actual ?? '-'} m, not ${planned ?? '-'} m.',
    );
  }
  return (
    level: WarningLevel.mild,
    text: 'Analysed ${gasMixName(o2Percent, hePercent)}, '
        'target ${target.name}',
  );
}
