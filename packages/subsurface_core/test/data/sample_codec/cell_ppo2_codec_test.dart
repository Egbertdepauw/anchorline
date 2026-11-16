import 'dart:typed_data';

import 'package:subsurface_core/data/models/sample_set.dart';
import 'package:subsurface_core/data/sample_codec/sample_codec.dart';
import 'package:test/test.dart';

SampleSet _samples(int n, {List<Float32List> cellPpo2Bar = const []}) {
  Float32List f() => Float32List(n);
  return SampleSet(
    diveId: 'd',
    sampleCount: n,
    sampleIntervalMs: 10000,
    depthMeters: f(),
    temperatureCelsius: f(),
    ppo2Bar: f(),
    cellMv0: f(),
    cellMv1: f(),
    cellMv2: f(),
    setpointBar: f(),
    cns: f(),
    decoStopDepthMeters: f(),
    decoTimeSeconds: Int32List(n),
    ttsSeconds: Int32List(n),
    gasMixIndex: Uint8List(n),
    statusFlags: Uint8List(n),
    cellPpo2Bar: cellPpo2Bar,
  );
}

SampleSet _roundTrip(SampleSet s) => SampleCodec.decode(
      blobs: SampleCodec.encode(s),
      diveId: s.diveId,
      sampleCount: s.sampleCount,
      sampleIntervalMs: s.sampleIntervalMs,
    );

void main() {
  test('four cell channels round-trip', () {
    const values = [0.70, 1.30, 1.29, 1.31];
    final channels = [
      for (final v in values) Float32List.fromList(List.filled(50, v)),
    ];
    final out = _roundTrip(_samples(50, cellPpo2Bar: channels));
    expect(out.cellPpo2Bar, hasLength(4));
    for (var i = 0; i < 4; i++) {
      expect(out.cellPpo2Bar[i], equals(channels[i]));
    }
  });

  test('a blob map without cellPpo2 decodes to an empty list', () {
    final blobs = SampleCodec.encode(_samples(5));
    blobs.remove('cellPpo2');
    final out = SampleCodec.decode(
      blobs: blobs,
      diveId: 'd',
      sampleCount: 5,
      sampleIntervalMs: 10000,
    );
    expect(out.cellPpo2Bar, isEmpty);
  });

  test('an empty cellPpo2Bar writes no cellPpo2 key', () {
    expect(SampleCodec.encode(_samples(5)).containsKey('cellPpo2'), isFalse);
  });
}
