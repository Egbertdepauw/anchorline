/// Grades an analysed gas against the mix the diver wanted.
///
/// Pure Dart, no Flutter imports. Inputs are PERCENTAGES (0–100). The
/// analyzer screen uses [gradeMix] for the green/orange/red colouring of the
/// analysed numbers, and the label flow uses [MixMatchLevel.hard] to warn
/// before printing a label for a gas that is not what was asked for.
///
/// Each gas is graded on its own by the absolute difference in percentage
/// points, rounded to 0.1 before comparing, and the overall level is the
/// worse of the two:
///
/// | Level    | O2 off by | He off by |
/// |----------|-----------|-----------|
/// | `match`  | ≤ 1.0     | ≤ 2.0     |
/// | `orange` | ≤ 2.0     | ≤ 4.0     |
/// | `red`    | ≤ 5.0     | ≤ 10.0    |
/// | `hard`   | > 5.0     | > 10.0    |
///
/// The O2 bounds and the hard limits (5.0 O2, 10.0 He) are Egbert's. The He
/// match, orange and red bounds (2.0, 4.0) were scaled from the O2 ones.
library;

/// Largest O2 difference (percentage points) that still counts as a match.
const double kO2MatchMax = 1.0;

/// Largest O2 difference that is orange; above [kO2MatchMax].
const double kO2OrangeMax = 2.0;

/// Largest O2 difference that is red; above it is a hard mismatch.
const double kO2RedMax = 5.0;

/// Largest He difference (percentage points) that still counts as a match.
const double kHeMatchMax = 2.0;

/// Largest He difference that is orange; above [kHeMatchMax].
const double kHeOrangeMax = 4.0;

/// Largest He difference that is red; above it is a hard mismatch.
const double kHeRedMax = 10.0;

/// How well an analysed gas matches the desired mix, best to worst.
enum MixMatchLevel { match, orange, red, hard }

/// The result of [gradeMix]: the overall [level] and how far each gas is
/// from the target, as absolute differences in percentage points rounded to
/// 0.1.
class MixMatch {
  final MixMatchLevel level;
  final double o2Off;
  final double heOff;

  const MixMatch({
    required this.level,
    required this.o2Off,
    required this.heOff,
  });
}

/// Grades [o2Percent]/[hePercent] against the target mix. Below the target
/// grades exactly like above it. The level is the worse of the O2 and He
/// levels.
MixMatch gradeMix({
  required double o2Percent,
  required double hePercent,
  required int targetO2Percent,
  required int targetHePercent,
}) {
  final o2Off = _roundedDiff(o2Percent, targetO2Percent);
  final heOff = _roundedDiff(hePercent, targetHePercent);
  final o2Level = _level(o2Off, kO2MatchMax, kO2OrangeMax, kO2RedMax);
  final heLevel = _level(heOff, kHeMatchMax, kHeOrangeMax, kHeRedMax);
  return MixMatch(
    level: o2Level.index >= heLevel.index ? o2Level : heLevel,
    o2Off: o2Off,
    heOff: heOff,
  );
}

/// One-line explanation of a grade for the card and the log:
/// `Matches Tx21/35` for a match, otherwise each gas that is above its match
/// bound with its difference, e.g. `O2 1.5 off Tx21/35` or
/// `O2 1.5, He 4.5 off Tx21/35`. [desiredName] is the name of the desired
/// mix, as produced by `gasMixName`.
String mixMatchText(MixMatch m, String desiredName) {
  final parts = <String>[
    if (m.o2Off > kO2MatchMax) 'O2 ${m.o2Off.toStringAsFixed(1)}',
    if (m.heOff > kHeMatchMax) 'He ${m.heOff.toStringAsFixed(1)}',
  ];
  if (parts.isEmpty) return 'Matches $desiredName';
  return '${parts.join(', ')} off $desiredName';
}

/// Absolute difference rounded to 0.1, so float noise such as
/// 22.1 - 21 = 1.1000000000000014 cannot tip a threshold compare.
double _roundedDiff(double measured, int target) =>
    (((measured - target).abs()) * 10).round() / 10;

MixMatchLevel _level(double off, double matchMax, double orangeMax,
    double redMax) {
  if (off <= matchMax) return MixMatchLevel.match;
  if (off <= orangeMax) return MixMatchLevel.orange;
  if (off <= redMax) return MixMatchLevel.red;
  return MixMatchLevel.hard;
}
