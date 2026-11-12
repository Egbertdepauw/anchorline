import 'dart:typed_data';

import 'package:subsurface_core/data/models/sample_set.dart';

/// Builds a [SampleSet] from plain lists; unspecified channels are zero.
SampleSet makeSampleSet({
  required String diveId,
  required int intervalMs,
  required List<double> depth,
  List<double>? ppo2,
  List<double>? setpoint,
  List<double>? cell0,
  List<double>? cell1,
  List<double>? cell2,
  List<double>? decoDepth,
}) {
  final n = depth.length;
  Float32List f(List<double>? v) =>
      Float32List.fromList(v ?? List<double>.filled(n, 0));
  return SampleSet(
    diveId: diveId,
    sampleCount: n,
    sampleIntervalMs: intervalMs,
    depthMeters: f(depth),
    temperatureCelsius: f(null),
    ppo2Bar: f(ppo2),
    cellMv0: f(cell0),
    cellMv1: f(cell1),
    cellMv2: f(cell2),
    setpointBar: f(setpoint),
    cns: f(null),
    decoStopDepthMeters: f(decoDepth),
    decoTimeSeconds: Int32List(n),
    ttsSeconds: Int32List(n),
    gasMixIndex: Uint8List(n),
    statusFlags: Uint8List(n),
  );
}
