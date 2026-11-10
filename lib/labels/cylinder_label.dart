/// The values and strings on a 50 × 30 mm cylinder label (issue #114).
///
/// Pure Dart, no Flutter imports. A [CylinderLabel] is built from a saved
/// [GasAnalysis] plus the "Use 1.4 for deeper mixes" setting, and carries
/// every number and string the renderer draws, so the renderer never
/// decides anything about gas.
///
/// Safety rules, all exercised in `cylinder_label_test.dart`:
///
/// * Depths come from the ANALYSED O2, never the desired one (see
///   [limitDepthMeters], issue #145). At or below the desired O2 they are
///   the nearest 3 m stop at which the gas stays at or under ppO2 1.6, as
///   divers quote them (EAN50 21 m, Tx21/35 at 1.4 57 m). Above the desired
///   O2 they are the exact depth rounded down to whole metres.
/// * The bailout/deco ppO2 is 1.6, or 1.4 for mixes under 50 % O2 when the
///   setting is on. The 50 % test uses the DESIRED O2, so an EAN50 that
///   analyses at 49.6 % keeps 1.6. With no desired mix, or on a hard
///   mismatch, it uses the analysed O2 rounded to a whole percent.
/// * The diluent label always uses 1.1 / 1.3 / 1.6, whatever the setting.
/// * Numbers and the date are formatted by hand or with a fixed English
///   locale, so a Dutch device prints `20.6` and `31 Oct 26`, not `20,6`
///   and `31 okt 26`.
library;

import 'package:intl/intl.dart';

import '../analysis/gas_naming.dart';
import '../analysis/mix_match.dart';
import '../analysis/mod.dart';
import '../data/models/gas_analysis.dart';

/// ppO2 (bar) for the bailout/deco MOD unless [kUse14BelowO2Percent] applies.
const double kBailoutModPpo2 = 1.6;

/// ppO2 (bar) for bailout/deco mixes under [kUse14BelowO2Percent] when
/// "Use 1.4 for deeper mixes" is on.
const double kDeeperMixModPpo2 = 1.4;

/// Mixes under this O2 percentage use [kDeeperMixModPpo2] when the setting
/// is on; mixes at or above it keep [kBailoutModPpo2].
const int kUse14BelowO2Percent = 50;

/// Diluent label: the headline TOD ppO2 (the analyzer's "CCR dil" limit).
const double kDiluentTodPpo2 = 1.1;

/// Diluent label: the high-setpoint depth ppO2.
const double kDiluentSetpointPpo2 = 1.3;

/// Diluent label: the MOD ppO2.
const double kDiluentModPpo2 = 1.6;

/// Shown instead of a depth that can't be worked out (no oxygen).
const String _noDepth = '–';

// Fixed English format so the label reads the same on every device locale.
final DateFormat _dateFormat = DateFormat('d MMM yy', 'en_US');

/// The depth, in whole metres, shown for where a gas with [o2Percent] %
/// oxygen reaches [ppO2] bar (issue #145).
///
/// * With no [desiredO2Percent], or an analysed O2 at or below it: the
///   nearest 3 m stop, one stop shallower while the gas would be above
///   ppO2 1.6 there ([roundToStopDepth]). EAN50 analysed at 49 % is 21 m;
///   at 47 % it is 24 m.
/// * With an analysed O2 above [desiredO2Percent]: the exact depth rounded
///   down to whole metres ([floorDepthTolerant]). EAN50 analysed at 52 %
///   is 20 m, not the 18 m stop.
///
/// "Above" compares the O2 as the label shows it, to one decimal, so a
/// difference the diver can't see never moves the depth. Callers pass no
/// [desiredO2Percent] on a hard mismatch, where the label names the
/// analysed gas.
///
/// Null when there is no usable depth: no oxygen (not finite) or a gas
/// that already exceeds [ppO2] at the surface (below 0).
int? limitDepthMeters(
  double o2Percent,
  double ppO2, {
  int? desiredO2Percent,
}) {
  final fO2 = o2Percent / 100.0;
  final m = modMeters(fO2, ppO2);
  if (!m.isFinite || m < 0) return null;
  final shownO2 = double.parse(o2Percent.toStringAsFixed(1));
  final aboveDesired =
      desiredO2Percent != null && shownO2 > desiredO2Percent;
  return aboveDesired ? floorDepthTolerant(m) : roundToStopDepth(m, fO2);
}

/// The ppO2 for the bailout/deco MOD. [o2PercentForRule] is the O2 the rule
/// is judged on (see the library comment), in whole percent.
double bailoutModPpo2({
  required int o2PercentForRule,
  required bool use14ForDeeperMixes,
}) =>
    use14ForDeeperMixes && o2PercentForRule < kUse14BelowO2Percent
        ? kDeeperMixModPpo2
        : kBailoutModPpo2;

/// Which layout a label uses.
enum CylinderLabelKind { bailout, diluent }

/// Everything printed on one label. Build it with
/// [CylinderLabel.fromAnalysis]; the constructor is public for renderer
/// tests that need a specific label.
class CylinderLabel {
  final CylinderLabelKind kind;

  /// The name in the black bar: the desired mix name, or the analysed one
  /// on a hard mismatch or with no desired mix.
  final String mixName;

  /// The initials typed when analysing, trimmed. Null when blank.
  final String? analysedBy;

  /// The big number in whole metres (MOD on bailout, TOD on diluent). Null
  /// when there is no usable depth.
  final int? headlineMeters;

  /// The ppO2 the headline is worked out at.
  final double headlinePpo2;

  /// Analysed O2 and He in percent. [hePercent] is null for a gas without
  /// helium (below `kHeliumNoiseFloorPercent`).
  final double o2Percent;
  final double? hePercent;

  final DateTime analysedAt;

  /// Diluent only (null on bailout): depth at ppO2 1.3 and MOD at ppO2 1.6.
  final int? setpointMeters;
  final int? mod16Meters;

  const CylinderLabel({
    required this.kind,
    required this.mixName,
    required this.analysedBy,
    required this.headlineMeters,
    required this.headlinePpo2,
    required this.o2Percent,
    required this.hePercent,
    required this.analysedAt,
    this.setpointMeters,
    this.mod16Meters,
  });

  /// The label for [a]. [use14ForDeeperMixes] is the device-local "Use 1.4
  /// for deeper mixes" setting; it only affects bailout/deco labels.
  factory CylinderLabel.fromAnalysis(
    GasAnalysis a, {
    required bool use14ForDeeperMixes,
  }) {
    // Up to red the label names the gas the diver asked for. A hard
    // mismatch, or no desired mix, names the gas that is really in the
    // cylinder, and the 50 % rule follows that name.
    final desired = a.desiredMix;
    final hard = a.match?.level == MixMatchLevel.hard;
    final String mixName;
    final int o2PercentForRule;
    // The desired O2 the depths are judged against; none when the label
    // names the analysed gas.
    final int? depthDesiredO2;
    if (desired == null || hard) {
      mixName = gasMixName(a.o2Percent, a.hePercent);
      o2PercentForRule = a.o2Percent.round();
      depthDesiredO2 = null;
    } else {
      mixName = desired.name;
      o2PercentForRule = desired.o2Percent;
      depthDesiredO2 = desired.o2Percent;
    }
    int? depth(double ppO2) => limitDepthMeters(a.o2Percent, ppO2,
        desiredO2Percent: depthDesiredO2);

    final by = a.analysedBy?.trim();
    final he = a.hePercent < kHeliumNoiseFloorPercent ? null : a.hePercent;
    final diluent = a.gasRole == GasRole.diluent;

    final double headlinePpo2 = diluent
        ? kDiluentTodPpo2
        : bailoutModPpo2(
            o2PercentForRule: o2PercentForRule,
            use14ForDeeperMixes: use14ForDeeperMixes,
          );

    return CylinderLabel(
      kind: diluent ? CylinderLabelKind.diluent : CylinderLabelKind.bailout,
      mixName: mixName,
      analysedBy: (by == null || by.isEmpty) ? null : by,
      headlineMeters: depth(headlinePpo2),
      headlinePpo2: headlinePpo2,
      o2Percent: a.o2Percent,
      hePercent: he,
      analysedAt: a.analysedAt,
      setpointMeters: diluent ? depth(kDiluentSetpointPpo2) : null,
      mod16Meters: diluent ? depth(kDiluentModPpo2) : null,
    );
  }

  /// The sample printed by Settings → "Print test label": desired Tx21/35,
  /// analysed 20.6 / 33.8, bailout, no initials.
  factory CylinderLabel.testLabel({
    required DateTime now,
    required bool use14ForDeeperMixes,
  }) =>
      CylinderLabel.fromAnalysis(
        GasAnalysis(
          id: 'test-label',
          analysedAt: now,
          o2Percent: 20.6,
          hePercent: 33.8,
          stable: true,
          targetO2Percent: 21,
          targetHePercent: 35,
        ),
        use14ForDeeperMixes: use14ForDeeperMixes,
      );

  bool get _isDiluent => kind == CylinderLabelKind.diluent;

  /// The outlined tag after the bar's left edge: `DIL`, or null on bailout.
  String? get barTag => _isDiluent ? 'DIL' : null;

  /// The big number: whole metres, or a dash when there is no usable depth.
  /// The renderer adds the unit.
  String get headlineText => headlineMeters?.toString() ?? _noDepth;

  /// The small line under the headline: `MOD 1.6`, `MOD 1.4` or `TOD 1.1`.
  String get headlineCaption =>
      '${_isDiluent ? 'TOD' : 'MOD'} ${_ppo2Text(headlinePpo2)}';

  /// Diluent only: `1.3: 53 m`.
  String? get diluentLeft => _isDiluent
      ? '${_ppo2Text(kDiluentSetpointPpo2)}: ${_depthText(setpointMeters)}'
      : null;

  /// Diluent only: `MOD 1.6: 67 m`.
  String? get diluentRight => _isDiluent
      ? 'MOD ${_ppo2Text(kDiluentModPpo2)}: ${_depthText(mod16Meters)}'
      : null;

  /// `O2 20.6  He 33.8` (two spaces), or `O2 32.1` for a gas without helium.
  String get footerLeft {
    final he = hePercent;
    final o2Text = 'O2 ${o2Percent.toStringAsFixed(1)}';
    return he == null ? o2Text : '$o2Text  He ${he.toStringAsFixed(1)}';
  }

  /// The analysis date: `31 Oct 26`.
  String get footerRight => _dateFormat.format(analysedAt);
}

String _ppo2Text(double ppO2) => ppO2.toStringAsFixed(1);

String _depthText(int? meters) => meters == null ? _noDepth : '$meters m';
