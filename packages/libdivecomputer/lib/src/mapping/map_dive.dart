import 'dart:typed_data';

import 'package:subsurface_core/subsurface_core.dart';

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
/// time. `Dive.dcFingerprint` is not set here; the importer sets it.
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
  // translated to the remaining list.
  final gasMixes = <DiveGasMix>[];
  final gasMap = <int?>[];
  for (final g in p.gasMixes) {
    if (g.usage == LibdcUsage.oxygen) {
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
  int? gasIndex(int i) => i >= 0 && i < gasMap.length ? gasMap[i] : null;

  final tanks = <DiveTank>[
    for (var i = 0; i < p.tanks.length; i++)
      DiveTank(
        slot: i,
        usage: _tankUsage(p.tanks[i].usage),
        name: '',
        serial: 0,
        beginPressureBar: p.tanks[i].beginPressureBar,
        endPressureBar: p.tanks[i].endPressureBar,
        pressureMaxBar: p.tanks[i].workPressureBar.round(),
        pressureReserveBar: 0,
      ),
  ];

  final grid = resample(p.rows, gasIndex: gasIndex, tankCount: tanks.length);

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
    dcVendor: e.vendor,
    dcProduct: e.product,
    dcFamily: e.family,
    dcModelCode: e.devinfoModel ?? e.descriptorModel,
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
