import 'dart:typed_data';

import 'package:subsurface_core/subsurface_core.dart';

import '../dive_id.dart';
import '../envelope.dart';
import '../parse/parsed_dive.dart';
import '../parse/status.dart';
import 'events.dart';
import 'resample.dart';

/// Turns what libdivecomputer parsed into Anchorline's own dive. Pure Dart;
/// the units follow `DiveConverter.convert`. Every change here bumps
/// `kLibdcParserVersion`.
///
/// Throws [LibdcParseException] (`dataFormat`) when the dive has no start
/// time. `Dive.dcFingerprint` is the envelope's fingerprint as lower-case hex.
ConvertedDive mapLibdcDive(
  LibdcParsedDive p,
  LibdcEnvelope e, {
  required String diveId,
}) {
  final wallClock = p.wallClock;
  if (wallClock == null) {
    throw const LibdcParseException(LibdcStatus.dataFormat);
  }

  // Gas mixes: oxygen-usage mixes are left out, and sample indexes are
  // translated to the remaining list. When that leaves nothing although the
  // parser reported mixes (a CCR whose only mix is its oxygen), keep them.
  final gasMixes = <DiveGasMix>[];
  final gasMap = <int?>[];
  void collect({required bool skipOxygen}) {
    gasMixes.clear();
    gasMap.clear();
    for (final g in p.gasMixes) {
      if (skipOxygen && g.usage == LibdcUsage.oxygen) {
        gasMap.add(null);
        continue;
      }
      gasMap.add(gasMixes.length);
      gasMixes.add(
        DiveGasMix(
          oxygenPercent: (g.oxygen * 100).round(),
          heliumPercent: (g.helium * 100).round(),
          isDiluent: g.usage == LibdcUsage.diluent,
        ),
      );
    }
  }

  collect(skipOxygen: true);
  if (gasMixes.isEmpty && p.gasMixes.isNotEmpty) collect(skipOxygen: false);
  // The deco replay needs at least one mix; a computer with none (gauge or
  // freedive) gets air, and every sample stays on index 0.
  if (gasMixes.isEmpty) {
    gasMixes.add(
      const DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: false),
    );
  }
  int? gasIndex(int i) => i >= 0 && i < gasMap.length ? gasMap[i] : null;

  final tanks = <DiveTank>[];
  final tankIndexes = <int>[];
  if (p.tanks.isNotEmpty) {
    for (var i = 0; i < p.tanks.length; i++) {
      final t = p.tanks[i];
      tankIndexes.add(i);
      tanks.add(
        DiveTank(
          slot: i,
          usage: _tankUsage(t.usage),
          name: '',
          serial: 0,
          beginPressureBar: t.beginPressureBar,
          endPressureBar: t.endPressureBar,
          pressureMaxBar: t.workPressureBar.round(),
          pressureReserveBar: 0,
        ),
      );
    }
  } else {
    // Some computers log tank pressure samples without any TANK field. Make
    // a tank for each index seen, with begin and end from the first and last
    // nonzero readings.
    final seen = <int>{for (final r in p.rows) ...r.pressures.keys}.toList()
      ..sort();
    for (final index in seen) {
      double begin = 0, end = 0;
      for (final r in p.rows) {
        final v = r.pressures[index];
        if (v == null || v == 0) continue;
        if (begin == 0) begin = v;
        end = v;
      }
      tankIndexes.add(index);
      tanks.add(
        DiveTank(
          slot: tanks.length,
          usage: TankUsage.none,
          name: '',
          serial: 0,
          beginPressureBar: begin,
          endPressureBar: end,
          pressureMaxBar: 0,
          pressureReserveBar: 0,
        ),
      );
    }
  }

  final grid = resample(
    p.rows,
    gasIndex: gasIndex,
    tankIndexes: tankIndexes,
    diveTimeSeconds: p.diveTimeSeconds,
  );

  // Time.
  final lastRowMs = p.rows.isEmpty
      ? 0
      : p.rows.map((r) => r.timeMs).reduce((a, b) => a > b ? a : b);
  final duration = Duration(
    seconds: p.diveTimeSeconds ?? (lastRowMs / 1000).round(),
  );
  final tz = p.timezoneSeconds;

  // Depth.
  var deepest = 0.0;
  for (final r in p.rows) {
    final d = r.depthM;
    if (d != null && d > deepest) deepest = d;
  }

  final mode =
      p.diveMode == null
      ? (p.rows.any((r) => (r.setpoint ?? 0) > 0)
            ? DiveMode.cc
            : DiveMode.ocTec)
      : switch (p.diveMode!) {
          LibdcDiveMode.ccr => DiveMode.cc,
          LibdcDiveMode.scr => DiveMode.sc,
          LibdcDiveMode.oc => DiveMode.ocTec,
          LibdcDiveMode.gauge => DiveMode.gauge,
          LibdcDiveMode.freedive => DiveMode.freedive,
        };

  final model = p.decoModel;
  final decoModel = switch (model?.type) {
    LibdcDecoModelType.vpm => DecoModel.vpmb,
    LibdcDecoModelType.dciem => DecoModel.dciem,
    _ => DecoModel.gf,
  };
  final isBuhlmann = model?.type == LibdcDecoModelType.buhlmann;

  final atmosphere = p.atmosphericBar;
  final salinity = p.salinity;
  final waterDensity = salinity == null
      ? 1020
      : salinity.density > 0
      ? salinity.density.round()
      : (salinity.water == LibdcWater.salt ? 1030 : 1000);

  final dive = Dive(
    id: diveId,
    dcSerial: e.devinfoSerial ?? 0,
    dcDiveNumber: 0,
    startTime: wallClock,
    endTime: wallClock.add(duration),
    utcOffsetMinutes: tz == null ? null : tz ~/ 60,
    duration: duration,
    maxDepthMeters: p.maxDepthM ?? deepest,
    diveMode: mode,
    decoModel: decoModel,
    gfLow: isBuhlmann ? (model!.gfLow ?? 0) : 0,
    gfHigh: isBuhlmann ? (model!.gfHigh ?? 0) : 0,
    atmosphericPressureMbar: atmosphere != null && atmosphere > 0
        ? (atmosphere * 1000).round()
        : 1013,
    waterDensityKgM3: waterDensity,
    logVersion: 0,
    dcModel: ShearwaterModel.unknown,
    gasMixes: gasMixes,
    tanks: tanks,
    sampleIntervalMs: grid.intervalMs,
    sensorCalibration: const [],
    // The model the computer reported, not the sibling the download opened.
    dcVendor: p.identityVendor ?? e.vendor,
    dcProduct: p.identityProduct ?? e.product,
    dcFamily: e.family,
    dcModelCode: e.devinfoModel ?? e.descriptorModel,
    dcFingerprint: fingerprintHex(e.fingerprint),
  );

  final n = grid.count;
  final samples = SampleSet(
    diveId: diveId,
    sampleCount: n,
    sampleIntervalMs: grid.intervalMs,
    depthMeters: grid.depth,
    temperatureCelsius: grid.temperature,
    ppo2Bar: grid.ppo2,
    cellMv0: Float32List(n),
    cellMv1: Float32List(n),
    cellMv2: Float32List(n),
    setpointBar: grid.setpoint,
    cns: grid.cns,
    decoStopDepthMeters: grid.decoStopDepth,
    decoTimeSeconds: grid.decoTime,
    ttsSeconds: grid.tts,
    gasMixIndex: grid.gasMixIndex,
    statusFlags: Uint8List(n),
    tankPressuresBar: grid.tankPressures,
    cellPpo2Bar: grid.cellPpo2,
  );

  return ConvertedDive(
    dive: dive,
    samples: samples,
    events: buildEvents(p.rows, gasIndex: gasIndex),
  );
}

TankUsage _tankUsage(LibdcUsage u) => switch (u) {
  LibdcUsage.none => TankUsage.none,
  LibdcUsage.oxygen => TankUsage.oxygen,
  LibdcUsage.diluent => TankUsage.diluent,
  LibdcUsage.sidemount => TankUsage.sidemount,
};
