import 'dart:io';
import 'dart:typed_data';

import 'package:ccrlogger/data/models/sample_set.dart';
import 'package:ccrlogger/data/sample_codec/sample_codec.dart';
import 'package:ccrlogger/shearwater/parser/dive_converter.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:flutter_test/flutter_test.dart';

SampleSet _loadRealSamples() {
  final data = File('test/fixtures/dives/dive_718.bin').readAsBytesSync();
  final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
  final parsed = parser.parse(data);
  final converted = DiveConverter.convert(
    parsed: parsed,
    dcSerial: 0xB89641E4,
    dcDiveNumber: 718,
    dcModel: ShearwaterModel.petrel3,
  );
  return converted.samples;
}

void main() {
  group('SampleCodec round-trip', () {
    test('encodes and decodes real dive samples losslessly', () {
      final original = _loadRealSamples();
      final blobs = SampleCodec.encode(original);
      final decoded = SampleCodec.decode(
        blobs: blobs,
        diveId: original.diveId,
        sampleCount: original.sampleCount,
        sampleIntervalMs: original.sampleIntervalMs,
      );

      expect(decoded.sampleCount, equals(original.sampleCount));
      expect(decoded.diveId, equals(original.diveId));
      expect(decoded.sampleIntervalMs, equals(original.sampleIntervalMs));

      // Float32 columns
      expect(decoded.depthMeters, equals(original.depthMeters));
      expect(decoded.temperatureCelsius, equals(original.temperatureCelsius));
      expect(decoded.ppo2Bar, equals(original.ppo2Bar));
      expect(decoded.cellMv0, equals(original.cellMv0));
      expect(decoded.cellMv1, equals(original.cellMv1));
      expect(decoded.cellMv2, equals(original.cellMv2));
      expect(decoded.setpointBar, equals(original.setpointBar));
      expect(decoded.cns, equals(original.cns));
      expect(decoded.decoStopDepthMeters, equals(original.decoStopDepthMeters));

      // Int32 columns
      expect(decoded.decoTimeSeconds, equals(original.decoTimeSeconds));
      expect(decoded.ttsSeconds, equals(original.ttsSeconds));

      // Uint8 columns
      expect(decoded.gasMixIndex, equals(original.gasMixIndex));
      expect(decoded.statusFlags, equals(original.statusFlags));
    });

    test('encoded blobs are smaller than raw data', () {
      final original = _loadRealSamples();
      final blobs = SampleCodec.encode(original);

      // Raw size: sampleCount * (13 float32 + 2 int32 + 2 uint8) columns
      // = n * (13*4 + 2*4 + 2) = n * 62 bytes
      final rawSize = original.sampleCount * 62;
      final blobSize = blobs.values.fold<int>(
          0, (sum, blob) => sum + blob.length);

      expect(blobSize, lessThan(rawSize),
          reason: 'Compressed should be smaller than raw');
    });

    test('partial decode: depth only', () {
      final original = _loadRealSamples();
      final blobs = SampleCodec.encode(original);
      final depth = SampleCodec.decodeDepth(
          blobs['depth']!, original.sampleCount);
      expect(depth, equals(original.depthMeters));
    });

    test('partial decode: ppo2 only', () {
      final original = _loadRealSamples();
      final blobs = SampleCodec.encode(original);
      final ppo2 = SampleCodec.decodePpo2(
          blobs['ppo2']!, original.sampleCount);
      expect(ppo2, equals(original.ppo2Bar));
    });
  });

  group('SampleCodec edge cases', () {
    test('handles single-sample dive', () {
      final single = SampleSet(
        diveId: 'test',
        sampleCount: 1,
        sampleIntervalMs: 10000,
        depthMeters: Float32List.fromList([5.0]),
        temperatureCelsius: Float32List.fromList([20.0]),
        ppo2Bar: Float32List.fromList([1.3]),
        cellMv0: Float32List.fromList([0.5]),
        cellMv1: Float32List.fromList([0.5]),
        cellMv2: Float32List.fromList([0.5]),
        setpointBar: Float32List.fromList([1.3]),
        cns: Float32List.fromList([0.1]),
        decoStopDepthMeters: Float32List.fromList([0.0]),
        decoTimeSeconds: Int32List.fromList([0]),
        ttsSeconds: Int32List.fromList([0]),
        gasMixIndex: Uint8List.fromList([0]),
        statusFlags: Uint8List.fromList([0]),
      );

      final blobs = SampleCodec.encode(single);
      final decoded = SampleCodec.decode(
        blobs: blobs,
        diveId: 'test',
        sampleCount: 1,
        sampleIntervalMs: 10000,
      );

      expect(decoded.depthMeters[0], equals(5.0));
      expect(decoded.temperatureCelsius[0], equals(20.0));
    });
  });
}
