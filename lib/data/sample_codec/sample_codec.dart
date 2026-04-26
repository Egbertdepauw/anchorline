/// Encodes [SampleSet] to column blobs for database storage and back.
///
/// Each column is independently gzipped via [ColumnPacker], allowing
/// partial reads (e.g., only depth + ppo2 for the profile chart).
library;

import 'dart:typed_data';

import '../models/sample_set.dart';
import 'column_packer.dart';

class SampleCodec {
  /// Encode a [SampleSet] into a map of column name → gzipped blob.
  static Map<String, Uint8List> encode(SampleSet samples) {
    return {
      'depth': ColumnPacker.packFloat32(samples.depthMeters),
      'temperature': ColumnPacker.packFloat32(samples.temperatureCelsius),
      'ppo2': ColumnPacker.packFloat32(samples.ppo2Bar),
      'cellMv0': ColumnPacker.packFloat32(samples.cellMv0),
      'cellMv1': ColumnPacker.packFloat32(samples.cellMv1),
      'cellMv2': ColumnPacker.packFloat32(samples.cellMv2),
      'setpoint': ColumnPacker.packFloat32(samples.setpointBar),
      'cns': ColumnPacker.packFloat32(samples.cns),
      'decoDepth': ColumnPacker.packFloat32(samples.decoStopDepthMeters),
      'decoTime': ColumnPacker.packInt32(samples.decoTimeSeconds),
      'tts': ColumnPacker.packInt32(samples.ttsSeconds),
      'gasMixIdx': ColumnPacker.packUint8(samples.gasMixIndex),
      'status': ColumnPacker.packUint8(samples.statusFlags),
    };
  }

  /// Decode column blobs back into a [SampleSet].
  static SampleSet decode({
    required Map<String, Uint8List> blobs,
    required String diveId,
    required int sampleCount,
    required int sampleIntervalMs,
  }) {
    return SampleSet(
      diveId: diveId,
      sampleCount: sampleCount,
      sampleIntervalMs: sampleIntervalMs,
      depthMeters: ColumnPacker.unpackFloat32(blobs['depth']!, sampleCount),
      temperatureCelsius:
          ColumnPacker.unpackFloat32(blobs['temperature']!, sampleCount),
      ppo2Bar: ColumnPacker.unpackFloat32(blobs['ppo2']!, sampleCount),
      cellMv0: ColumnPacker.unpackFloat32(blobs['cellMv0']!, sampleCount),
      cellMv1: ColumnPacker.unpackFloat32(blobs['cellMv1']!, sampleCount),
      cellMv2: ColumnPacker.unpackFloat32(blobs['cellMv2']!, sampleCount),
      setpointBar:
          ColumnPacker.unpackFloat32(blobs['setpoint']!, sampleCount),
      cns: ColumnPacker.unpackFloat32(blobs['cns']!, sampleCount),
      decoStopDepthMeters:
          ColumnPacker.unpackFloat32(blobs['decoDepth']!, sampleCount),
      decoTimeSeconds:
          ColumnPacker.unpackInt32(blobs['decoTime']!, sampleCount),
      ttsSeconds: ColumnPacker.unpackInt32(blobs['tts']!, sampleCount),
      gasMixIndex:
          ColumnPacker.unpackUint8(blobs['gasMixIdx']!, sampleCount),
      statusFlags:
          ColumnPacker.unpackUint8(blobs['status']!, sampleCount),
    );
  }

  /// Decode only the depth column (for lightweight profile rendering).
  static Float32List decodeDepth(Uint8List blob, int sampleCount) =>
      ColumnPacker.unpackFloat32(blob, sampleCount);

  /// Decode only the PPO2 column.
  static Float32List decodePpo2(Uint8List blob, int sampleCount) =>
      ColumnPacker.unpackFloat32(blob, sampleCount);
}
