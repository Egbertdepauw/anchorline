import 'dart:typed_data';

import 'package:libdivecomputer/libdivecomputer.dart';

/// An envelope for mapping tests. [serial] null means the computer sent no
/// device info.
LibdcEnvelope testEnvelope({int? serial = 1234567, int? model = 10}) =>
    LibdcEnvelope(
      pinnedCommit: '0194f09',
      vendor: 'Divesoft',
      product: 'Liberty',
      family: 0x130000,
      descriptorModel: 10,
      devinfoModel: serial == null ? null : model,
      devinfoFirmware: serial == null ? null : 1,
      devinfoSerial: serial,
      fingerprint: Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]),
      data: Uint8List.fromList([1, 2, 3]),
    );

/// A row at [timeMs].
LibdcSampleRow row(
  int timeMs, {
  double? depth,
  double? temp,
  double? ppo2,
  Map<int, double>? cells,
  double? setpoint,
  double? cns,
  LibdcDeco? deco,
  int? gas,
  Map<int, double>? pressures,
  List<LibdcSampleEvent>? events,
}) => LibdcSampleRow(
  timeMs: timeMs,
  depthM: depth,
  temperatureC: temp,
  ppo2Voted: ppo2,
  cells: cells,
  setpoint: setpoint,
  cns: cns,
  deco: deco,
  gasMix: gas,
  pressures: pressures,
  events: events,
);

/// A dive with a wall clock and the given pieces.
LibdcParsedDive testDive({
  DateTime? wallClock,
  bool noWallClock = false,
  int? timezoneSeconds,
  int? diveTimeSeconds,
  double? maxDepthM,
  double? atmosphericBar,
  LibdcSalinity? salinity,
  List<LibdcGasMix> gasMixes = const [],
  List<LibdcTank> tanks = const [],
  LibdcDiveMode? diveMode,
  LibdcDecoModel? decoModel,
  List<LibdcSampleRow> rows = const [],
}) => LibdcParsedDive(
  wallClock: noWallClock ? null : (wallClock ?? DateTime.utc(2026, 6, 1, 9, 30)),
  timezoneSeconds: timezoneSeconds,
  diveTimeSeconds: diveTimeSeconds,
  maxDepthM: maxDepthM,
  atmosphericBar: atmosphericBar,
  salinity: salinity,
  gasMixes: gasMixes,
  tanks: tanks,
  diveMode: diveMode,
  decoModel: decoModel,
  rows: rows,
);

/// libdivecomputer's event numbers.
const int evDecostop = 1;
const int evAscent = 3;
const int evCeiling = 4;
const int evViolation = 7;
const int evBookmark = 8;
const int evSurface = 9;
const int evDeepstop = 14;
const int evCeilingSafetystop = 15;
