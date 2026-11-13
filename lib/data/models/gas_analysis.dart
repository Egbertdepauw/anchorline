/// Cylinder analysis log entry (issue #111): one saved gas-analyzer
/// reading, optionally linked to a cylinder from Equipment.
///
/// Pure Dart. Only measured / typed values are stored; the mix label and
/// the MOD depths are derived here from [o2Percent] / [hePercent] so they
/// can never disagree with the numbers.
///
/// Two things the diver states rather than measures are stored too (issue
/// #114, cylinder labels): the DESIRED mix ([DesiredMix], whole percents)
/// and the [GasRole] the gas is for. They are editable afterwards, with the
/// notes, who analysed it, who it is for, the cylinder, the fill pressure and
/// the sign-off ([GasAnalysisEdit]). The measured values are not.
///
/// An analysis also records how it got into the log ([CaptureSource]) and
/// whether it still [GasAnalysis.needsSignoff] (issue #113, Log on OK).
library;

import 'dart:convert';

import '../../analysis/gas_naming.dart';
import '../../analysis/mix_match.dart';
import '../../analysis/mod.dart';
import 'equipment.dart';

/// What a gas is for, which decides the label layout and the ppO2s its
/// depths are worked out at. `bailout`, `backgas` and `deco` all print as a
/// bailout label; only `diluent` differs (issue #112).
enum GasRole {
  bailout,
  diluent,
  backgas,
  deco;

  /// The `gas_role` column value.
  String get dbValue => switch (this) {
        GasRole.bailout => 'bailout',
        GasRole.diluent => 'diluent',
        GasRole.backgas => 'backgas',
        GasRole.deco => 'deco',
      };

  /// Diver-facing name, for the role buttons.
  String get label => switch (this) {
        GasRole.bailout => 'Bailout',
        GasRole.diluent => 'Diluent',
        GasRole.backgas => 'Backgas',
        GasRole.deco => 'Deco',
      };

  /// Whether this is the CCR diluent role.
  bool get isDiluent => this == GasRole.diluent;

  /// Lenient on read: null, empty and unknown strings (a row from an older
  /// build or another device) all mean bailout.
  static GasRole fromDb(String? v) {
    for (final r in GasRole.values) {
      if (r.dbValue == v) return r;
    }
    return GasRole.bailout;
  }
}

/// The order the role buttons show the roles in.
const kGasRoleButtonOrder = [
  GasRole.diluent,
  GasRole.bailout,
  GasRole.backgas,
  GasRole.deco,
];

/// How an analysis got into the log (issue #113).
enum CaptureSource {
  /// Saved from the analyzer screen (every row before the bridge existed).
  screen,

  /// Captured by the SOLO bridge when the diver pressed OK.
  bridgeOk,

  /// Captured by the app itself when the diver pressed OK on a SOLO on a USB
  /// cable (Log on OK over USB, the analyzer screen open).
  usbOk;

  /// The `capture_source` column value: null for a screen save.
  String? get dbValue => switch (this) {
        CaptureSource.screen => null,
        CaptureSource.bridgeOk => 'bridge_ok',
        CaptureSource.usbOk => 'usb_ok',
      };

  /// Lenient on read: null and unknown strings (a row from an older build or
  /// another device) all mean a screen save.
  static CaptureSource fromDb(String? v) => switch (v) {
        'bridge_ok' => CaptureSource.bridgeOk,
        'usb_ok' => CaptureSource.usbOk,
        _ => CaptureSource.screen,
      };
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

  /// The entry waits in the log for the diver to sign it off.
  final bool needsSignoff;

  /// An analysis of what was left in the cylinder before a fill (issue
  /// #112): it closes no blend.
  final bool isResidual;
  final CaptureSource captureSource;

  /// The bridge's id for the capture (`<bridge>/<rid>`); null for a screen
  /// save.
  final String? bridgeRecordId;

  /// Who the gas is for (free text).
  final String? analysedFor;

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
    this.needsSignoff = false,
    this.isResidual = false,
    this.captureSource = CaptureSource.screen,
    this.bridgeRecordId,
    this.analysedFor,
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

  /// The entry waits in the log for the diver to sign it off (issue #113).
  final bool needsSignoff;

  /// Measured what was left in the cylinder before a fill (issue #112).
  final bool isResidual;
  final CaptureSource captureSource;
  final String? bridgeRecordId;
  final String? analysedFor;

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
    this.needsSignoff = false,
    this.isResidual = false,
    this.captureSource = CaptureSource.screen,
    this.bridgeRecordId,
    this.analysedFor,
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
        needsSignoff: n.needsSignoff,
        isResidual: n.isResidual,
        captureSource: n.captureSource,
        bridgeRecordId: n.bridgeRecordId,
        analysedFor: n.analysedFor,
      );

  /// This analysis with the editable fields replaced by [e]. Used by fakes;
  /// the DAO writes the same fields to the row. A different cylinder drops
  /// the joined [cylinderLabel] (the DAO joins it again on read; a fake
  /// resolves it itself). A [GasAnalysisEdit.signOff] clears [needsSignoff];
  /// without it the flag stays.
  GasAnalysis applyEdit(GasAnalysisEdit e) {
    final sameCylinder = e.cylinderId == cylinderId;
    return GasAnalysis(
      id: id,
      cylinderId: e.cylinderId,
      cylinderLabel: sameCylinder ? cylinderLabel : null,
      cylinderDeleted: sameCylinder ? cylinderDeleted : false,
      analysedBy: e.analysedBy,
      analysedAt: analysedAt,
      o2Percent: o2Percent,
      hePercent: hePercent,
      fillPressureBar: e.fillPressureBar,
      tempC: tempC,
      baroHpa: baroHpa,
      modPpo2s: modPpo2s,
      stable: stable,
      notes: e.notes,
      targetO2Percent: e.desiredMix?.o2Percent,
      targetHePercent: e.desiredMix?.hePercent,
      gasRole: e.gasRole,
      needsSignoff: e.signOff ? false : needsSignoff,
      isResidual: isResidual,
      captureSource: captureSource,
      bridgeRecordId: bridgeRecordId,
      analysedFor: e.analysedFor,
    );
  }

  /// This analysis with only [needsSignoff] changed to [value]. The joined
  /// cylinder label stays.
  GasAnalysis withNeedsSignoff(bool value) => GasAnalysis(
        id: id,
        cylinderId: cylinderId,
        cylinderLabel: cylinderLabel,
        cylinderDeleted: cylinderDeleted,
        analysedBy: analysedBy,
        analysedAt: analysedAt,
        o2Percent: o2Percent,
        hePercent: hePercent,
        fillPressureBar: fillPressureBar,
        tempC: tempC,
        baroHpa: baroHpa,
        modPpo2s: modPpo2s,
        stable: stable,
        notes: notes,
        targetO2Percent: targetO2Percent,
        targetHePercent: targetHePercent,
        gasRole: gasRole,
        needsSignoff: value,
        isResidual: isResidual,
        captureSource: captureSource,
        bridgeRecordId: bridgeRecordId,
        analysedFor: analysedFor,
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
/// measured values, [GasAnalysis.captureSource] and
/// [GasAnalysis.bridgeRecordId] never are. A null [desiredMix], [cylinderId],
/// [fillPressureBar] or [analysedFor] clears it. With [signOff] the entry
/// stops needing sign-off; without it the flag stays as it is.
class GasAnalysisEdit {
  final DesiredMix? desiredMix;
  final GasRole gasRole;
  final String? analysedBy;
  final String? notes;
  final String? cylinderId;
  final double? fillPressureBar;
  final String? analysedFor;
  final bool signOff;

  const GasAnalysisEdit({
    required this.desiredMix,
    required this.gasRole,
    required this.analysedBy,
    required this.notes,
    required this.cylinderId,
    required this.fillPressureBar,
    required this.analysedFor,
    this.signOff = false,
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
