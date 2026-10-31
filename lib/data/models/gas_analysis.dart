/// Cylinder analysis log entry (issue #111): one saved gas-analyzer
/// reading, optionally linked to a cylinder from Equipment.
///
/// Pure Dart. Only measured / typed values are stored; the mix label and
/// the MOD depths are derived here from [o2Percent] / [hePercent] so they
/// can never disagree with the numbers.
library;

import 'dart:convert';

import '../../analysis/gas_naming.dart';
import '../../analysis/mod.dart';

/// A cylinder the diver can attach an analysis to.
class CylinderChoice {
  final String id;
  final String label;
  const CylinderChoice({required this.id, required this.label});
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
  });

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
