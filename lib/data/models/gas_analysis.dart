/// Cylinder analysis log entry (issue #111): one saved gas-analyzer
/// reading, optionally linked to a cylinder from Equipment.
///
/// Pure Dart. Only measured / typed values are stored; the mix label and
/// the MOD depths are derived here from [o2Percent] / [hePercent] so they
/// can never disagree with the numbers.
///
/// Two things the diver states rather than measures are stored too (issue
/// #114, cylinder labels): the DESIRED mix ([DesiredMix], whole percents)
/// and the [GasRole] the gas is for. They are the only editable parts of a
/// saved analysis, besides the notes and who analysed it ([GasAnalysisEdit]).
library;

import 'dart:convert';

import '../../analysis/gas_naming.dart';
import '../../analysis/mix_match.dart';
import '../../analysis/mod.dart';
import 'equipment.dart';

/// What a gas is for, which decides the label layout and the ppO2s its
/// depths are worked out at. `bailout` also covers deco, stage and OC.
enum GasRole {
  bailout,
  diluent;

  /// The `gas_role` column value.
  String get dbValue => switch (this) {
        GasRole.bailout => 'bailout',
        GasRole.diluent => 'diluent',
      };

  /// Lenient on read: null, empty and unknown strings (a row from an older
  /// build or another device) all mean bailout/deco.
  static GasRole fromDb(String? v) =>
      v == 'diluent' ? GasRole.diluent : GasRole.bailout;
}

/// The role to preselect for a cylinder: diluent cylinders are diluent,
/// everything else (oxygen, bailout, offboard, no role) is bailout/deco.
GasRole gasRoleForCylinderRole(String? cylinderRole) =>
    cylinderRole == CylinderRole.diluent ? GasRole.diluent : GasRole.bailout;

/// The mix the diver wanted the cylinder to hold, in whole percents.
class DesiredMix {
  final int o2Percent;
  final int hePercent;

  const DesiredMix(this.o2Percent, this.hePercent);

  /// Diver-facing name (`Tx21/35`, `EAN32`, `Air`).
  String get name => gasMixName(o2Percent, hePercent);

  @override
  bool operator ==(Object other) =>
      other is DesiredMix &&
      other.o2Percent == o2Percent &&
      other.hePercent == hePercent;

  @override
  int get hashCode => Object.hash(o2Percent, hePercent);

  @override
  String toString() => 'DesiredMix($o2Percent, $hePercent)';
}

/// A cylinder the diver can attach an analysis to. [role] is the cylinder's
/// `CylinderRole` in Equipment (null for an unknown role).
class CylinderChoice {
  final String id;
  final String label;
  final String? role;
  const CylinderChoice({required this.id, required this.label, this.role});
}

/// The values captured when the diver taps "Save analysis".
class NewGasAnalysis {
  final String? cylinderId;
  final String? analysedBy;
  final DateTime analysedAt;
  final double o2Percent;
  final double hePercent;
  final double? fillPressureBar;
  final double? tempC;
  final double? baroHpa;
  final List<double> modPpo2s;
  final bool stable;
  final String? notes;
  final DesiredMix? desiredMix;
  final GasRole gasRole;

  const NewGasAnalysis({
    this.cylinderId,
    this.analysedBy,
    required this.analysedAt,
    required this.o2Percent,
    required this.hePercent,
    this.fillPressureBar,
    this.tempC,
    this.baroHpa,
    this.modPpo2s = const [],
    required this.stable,
    this.notes,
    this.desiredMix,
    this.gasRole = GasRole.bailout,
  });
}

/// A stored analysis as the log shows it. [cylinderLabel] is joined from
/// `cylinders` at read time; null when the analysis has no cylinder or the
/// cylinder row isn't known on this device. [cylinderDeleted] is true when
/// the linked cylinder was soft-deleted from Equipment.
class GasAnalysis {
  final String id;
  final String? cylinderId;
  final String? cylinderLabel;
  final bool cylinderDeleted;
  final String? analysedBy;
  final DateTime analysedAt;
  final double o2Percent;
  final double hePercent;
  final double? fillPressureBar;
  final double? tempC;
  final double? baroHpa;
  final List<double> modPpo2s;
  final bool stable;
  final String? notes;

  /// The desired mix as stored: whole percents. Null target O2 means none
  /// was set; a null target He then counts as 0. Read [desiredMix].
  final int? targetO2Percent;
  final int? targetHePercent;
  final GasRole gasRole;

  const GasAnalysis({
    required this.id,
    this.cylinderId,
    this.cylinderLabel,
    this.cylinderDeleted = false,
    this.analysedBy,
    required this.analysedAt,
    required this.o2Percent,
    required this.hePercent,
    this.fillPressureBar,
    this.tempC,
    this.baroHpa,
    this.modPpo2s = const [],
    required this.stable,
    this.notes,
    this.targetO2Percent,
    this.targetHePercent,
    this.gasRole = GasRole.bailout,
  });

  /// What [NewGasAnalysis] becomes once saved under [id]. [cylinderLabel]
  /// is the joined label that the DAO fills in on read.
  factory GasAnalysis.fromNew(String id, NewGasAnalysis n,
          {String? cylinderLabel}) =>
      GasAnalysis(
        id: id,
        cylinderId: n.cylinderId,
        cylinderLabel: cylinderLabel,
        analysedBy: n.analysedBy,
        analysedAt: n.analysedAt,
        o2Percent: n.o2Percent,
        hePercent: n.hePercent,
        fillPressureBar: n.fillPressureBar,
        tempC: n.tempC,
        baroHpa: n.baroHpa,
        modPpo2s: n.modPpo2s,
        stable: n.stable,
        notes: n.notes,
        targetO2Percent: n.desiredMix?.o2Percent,
        targetHePercent: n.desiredMix?.hePercent,
        gasRole: n.gasRole,
      );

  /// This analysis with the four editable fields replaced by [e]. Used by
  /// fakes; the DAO writes the same fields to the row.
  GasAnalysis applyEdit(GasAnalysisEdit e) => GasAnalysis(
        id: id,
        cylinderId: cylinderId,
        cylinderLabel: cylinderLabel,
        cylinderDeleted: cylinderDeleted,
        analysedBy: e.analysedBy,
        analysedAt: analysedAt,
        o2Percent: o2Percent,
        hePercent: hePercent,
        fillPressureBar: fillPressureBar,
        tempC: tempC,
        baroHpa: baroHpa,
        modPpo2s: modPpo2s,
        stable: stable,
        notes: e.notes,
        targetO2Percent: e.desiredMix?.o2Percent,
        targetHePercent: e.desiredMix?.hePercent,
        gasRole: e.gasRole,
      );

  /// The desired mix, or null when none was set (no target O2).
  DesiredMix? get desiredMix {
    final o2 = targetO2Percent;
    if (o2 == null) return null;
    return DesiredMix(o2, targetHePercent ?? 0);
  }

  /// How the measured gas compares with [desiredMix]; null without one.
  MixMatch? get match {
    final d = desiredMix;
    if (d == null) return null;
    return gradeMix(
      o2Percent: o2Percent,
      hePercent: hePercent,
      targetO2Percent: d.o2Percent,
      targetHePercent: d.hePercent,
    );
  }

  /// Diver-facing mix name, whole percentages (`Tx21/35`, `EAN32`, `Air`).
  String get mixName => gasMixName(o2Percent, hePercent);

  /// MOD in metres at [ppO2] (bar). Not finite or ≤ 0 means "no usable
  /// MOD" (no oxygen, or the gas exceeds [ppO2] at the surface).
  double modAt(double ppO2) => modMeters(o2Percent / 100.0, ppO2);

  /// Label for the cylinder column: the cylinder's name, "Unknown
  /// cylinder" for a dangling link, or null for no cylinder at all.
  String? get cylinderDisplay {
    if (cylinderId == null) return null;
    final label = cylinderLabel;
    if (label == null) return 'Unknown cylinder';
    return cylinderDeleted ? '$label (deleted)' : label;
  }
}

/// The only parts of a saved analysis the diver can change afterwards. The
/// measured values never are. A null [desiredMix] clears it.
class GasAnalysisEdit {
  final DesiredMix? desiredMix;
  final GasRole gasRole;
  final String? analysedBy;
  final String? notes;

  const GasAnalysisEdit({
    required this.desiredMix,
    required this.gasRole,
    required this.analysedBy,
    required this.notes,
  });
}

/// The desired mixes to offer as quick picks when saving an analysis: the
/// Blend tab's target first (when given), then the distinct desired mixes of
/// the first [lookback] analyses of [newestFirst], in order, with no
/// duplicates. Analyses without a desired mix use up a lookback slot but add
/// nothing.
List<DesiredMix> recentDesiredMixes(
  List<GasAnalysis> newestFirst, {
  DesiredMix? blendTarget,
  int lookback = 10,
}) {
  final out = <DesiredMix>[?blendTarget];
  for (final a in newestFirst.take(lookback)) {
    final d = a.desiredMix;
    if (d != null && !out.contains(d)) out.add(d);
  }
  return out;
}

/// `[1.1,1.4,1.6]` ↔ list of doubles. Lenient on read: bad JSON or
/// non-numbers decode to an empty list rather than failing the log.
String encodeModPpo2s(List<double> ppo2s) => jsonEncode(ppo2s);

List<double> decodeModPpo2s(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    final v = jsonDecode(json);
    if (v is! List) return const [];
    return [
      for (final e in v)
        if (e is num) e.toDouble(),
    ];
  } catch (_) {
    return const [];
  }
}
