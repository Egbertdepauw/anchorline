/// Data models for the Dive Plan tab. Plan bodies are JSON-encoded into
/// columns of the `dive_plans` table (see spec). Models are immutable
/// value classes with `==` / `hashCode` so notifier diffs are cheap.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Deepest segment the planner accepts. Deeper than any real CCR or
/// trimix dive; it exists to catch typos like 4030 instead of 40, which
/// produce well over a thousand deco stops and make the UI lag for
/// seconds on every rebuild.
const double kMaxPlanDepthMeters = 300;

@immutable
class DivePlanGas {
  final int oxygenPercent;
  final int heliumPercent;
  final bool isDiluent;
  const DivePlanGas({
    required this.oxygenPercent,
    required this.heliumPercent,
    required this.isDiluent,
  });

  Map<String, dynamic> toJson() => {
        'o2': oxygenPercent,
        'he': heliumPercent,
        'dil': isDiluent,
      };

  factory DivePlanGas.fromJson(Map<String, dynamic> j) => DivePlanGas(
        oxygenPercent: j['o2'] as int,
        heliumPercent: j['he'] as int,
        isDiluent: j['dil'] as bool,
      );

  @override
  bool operator ==(Object other) =>
      other is DivePlanGas &&
      other.oxygenPercent == oxygenPercent &&
      other.heliumPercent == heliumPercent &&
      other.isDiluent == isDiluent;

  @override
  int get hashCode => Object.hash(oxygenPercent, heliumPercent, isDiluent);
}

@immutable
class DivePlanSegment {
  final double depthMeters;
  final int durationMinutes; // 0 = instant change (gas / setpoint)
  final int gasMixIndex;
  final double? setpoint; // CC only; null = phase default
  const DivePlanSegment({
    required this.depthMeters,
    required this.durationMinutes,
    required this.gasMixIndex,
    this.setpoint,
  });

  Map<String, dynamic> toJson() => {
        'd': depthMeters,
        't': durationMinutes,
        'g': gasMixIndex,
        if (setpoint != null) 'sp': setpoint,
      };

  factory DivePlanSegment.fromJson(Map<String, dynamic> j) => DivePlanSegment(
        depthMeters: (j['d'] as num).toDouble(),
        durationMinutes: j['t'] as int,
        gasMixIndex: j['g'] as int,
        setpoint: (j['sp'] as num?)?.toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is DivePlanSegment &&
      other.depthMeters == depthMeters &&
      other.durationMinutes == durationMinutes &&
      other.gasMixIndex == gasMixIndex &&
      other.setpoint == setpoint;

  @override
  int get hashCode =>
      Object.hash(depthMeters, durationMinutes, gasMixIndex, setpoint);
}

@immutable
class DivePlanBailoutBottle {
  final int gasMixIndex;
  final double waterCapacityL;
  final int fillPressureBar;
  const DivePlanBailoutBottle({
    required this.gasMixIndex,
    required this.waterCapacityL,
    required this.fillPressureBar,
  });

  Map<String, dynamic> toJson() => {
        'g': gasMixIndex,
        'wc': waterCapacityL,
        'fp': fillPressureBar,
      };

  factory DivePlanBailoutBottle.fromJson(Map<String, dynamic> j) =>
      DivePlanBailoutBottle(
        gasMixIndex: j['g'] as int,
        waterCapacityL: (j['wc'] as num).toDouble(),
        fillPressureBar: j['fp'] as int,
      );

  @override
  bool operator ==(Object other) =>
      other is DivePlanBailoutBottle &&
      other.gasMixIndex == gasMixIndex &&
      other.waterCapacityL == waterCapacityL &&
      other.fillPressureBar == fillPressureBar;

  @override
  int get hashCode =>
      Object.hash(gasMixIndex, waterCapacityL, fillPressureBar);
}

@immutable
class DivePlanSettings {
  final int? gfLow;
  final int? gfHigh;
  final int? vpmbConservatism;
  final bool? useVpmb;
  final int? ascentRateMpm;
  final int? descentRateMpm;
  final double? bottomSetpoint;
  final double? ascentSetpoint;
  final double? decoSetpoint;
  final double? lastStopDepthMeters;
  final int? ocSac;
  // At/above this depth the planner switches the loop from the ascent
  // SP to the deco SP. Null = use the diver's default
  // (settings.plannerDecoSwitchDepthMeters).
  final double? decoSwitchDepthMeters;

  const DivePlanSettings({
    this.gfLow,
    this.gfHigh,
    this.vpmbConservatism,
    this.useVpmb,
    this.ascentRateMpm,
    this.descentRateMpm,
    this.bottomSetpoint,
    this.ascentSetpoint,
    this.decoSetpoint,
    this.lastStopDepthMeters,
    this.ocSac,
    this.decoSwitchDepthMeters,
  });

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (gfLow != null) m['gfLo'] = gfLow;
    if (gfHigh != null) m['gfHi'] = gfHigh;
    if (vpmbConservatism != null) m['vpmb'] = vpmbConservatism;
    if (useVpmb != null) m['useVpmb'] = useVpmb;
    if (ascentRateMpm != null) m['asc'] = ascentRateMpm;
    if (descentRateMpm != null) m['des'] = descentRateMpm;
    if (bottomSetpoint != null) m['spBot'] = bottomSetpoint;
    if (ascentSetpoint != null) m['spAsc'] = ascentSetpoint;
    if (decoSetpoint != null) m['spDec'] = decoSetpoint;
    if (lastStopDepthMeters != null) m['last'] = lastStopDepthMeters;
    if (ocSac != null) m['ocSac'] = ocSac;
    if (decoSwitchDepthMeters != null) m['spSwM'] = decoSwitchDepthMeters;
    return m;
  }

  factory DivePlanSettings.fromJson(Map<String, dynamic> j) =>
      DivePlanSettings(
        gfLow: j['gfLo'] as int?,
        gfHigh: j['gfHi'] as int?,
        vpmbConservatism: j['vpmb'] as int?,
        useVpmb: j['useVpmb'] as bool?,
        ascentRateMpm: j['asc'] as int?,
        descentRateMpm: j['des'] as int?,
        bottomSetpoint: (j['spBot'] as num?)?.toDouble(),
        ascentSetpoint: (j['spAsc'] as num?)?.toDouble(),
        decoSetpoint: (j['spDec'] as num?)?.toDouble(),
        lastStopDepthMeters: (j['last'] as num?)?.toDouble(),
        ocSac: j['ocSac'] as int?,
        decoSwitchDepthMeters: (j['spSwM'] as num?)?.toDouble(),
      );

  DivePlanSettings copyWith({
    int? gfLow,
    int? gfHigh,
    int? vpmbConservatism,
    bool? useVpmb,
    int? ascentRateMpm,
    int? descentRateMpm,
    double? bottomSetpoint,
    double? ascentSetpoint,
    double? decoSetpoint,
    double? lastStopDepthMeters,
    int? ocSac,
    double? decoSwitchDepthMeters,
  }) =>
      DivePlanSettings(
        gfLow: gfLow ?? this.gfLow,
        gfHigh: gfHigh ?? this.gfHigh,
        vpmbConservatism: vpmbConservatism ?? this.vpmbConservatism,
        useVpmb: useVpmb ?? this.useVpmb,
        ascentRateMpm: ascentRateMpm ?? this.ascentRateMpm,
        descentRateMpm: descentRateMpm ?? this.descentRateMpm,
        bottomSetpoint: bottomSetpoint ?? this.bottomSetpoint,
        ascentSetpoint: ascentSetpoint ?? this.ascentSetpoint,
        decoSetpoint: decoSetpoint ?? this.decoSetpoint,
        lastStopDepthMeters:
            lastStopDepthMeters ?? this.lastStopDepthMeters,
        ocSac: ocSac ?? this.ocSac,
        decoSwitchDepthMeters:
            decoSwitchDepthMeters ?? this.decoSwitchDepthMeters,
      );
}

enum DivePlanMode { cc, oc }

/// Encoders / decoders for the JSON columns. Kept as top-level
/// functions so the DAO doesn't reach into instance state.
String encodeGases(List<DivePlanGas> gases) =>
    jsonEncode(gases.map((g) => g.toJson()).toList());

List<DivePlanGas> decodeGases(String s) =>
    (jsonDecode(s) as List).map((j) => DivePlanGas.fromJson(j as Map<String, dynamic>)).toList();

String encodeSegments(List<DivePlanSegment> segs) =>
    jsonEncode(segs.map((s) => s.toJson()).toList());

List<DivePlanSegment> decodeSegments(String s) => (jsonDecode(s) as List)
    .map((j) => DivePlanSegment.fromJson(j as Map<String, dynamic>))
    .toList();

String encodeBailout(List<DivePlanBailoutBottle> bs) =>
    jsonEncode(bs.map((b) => b.toJson()).toList());

List<DivePlanBailoutBottle> decodeBailout(String s) =>
    (jsonDecode(s) as List)
        .map((j) => DivePlanBailoutBottle.fromJson(j as Map<String, dynamic>))
        .toList();

String? encodeSettings(DivePlanSettings? s) =>
    s == null ? null : jsonEncode(s.toJson());

DivePlanSettings? decodeSettings(String? s) =>
    s == null ? null : DivePlanSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
