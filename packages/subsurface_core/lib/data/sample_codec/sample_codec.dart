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
  ///
  /// `tankPressures` is only present when the SampleSet has at least one
  /// tank channel; absent for OC dives and older imports.
  static Map<String, Uint8List> encode(SampleSet samples) {
    final out = <String, Uint8List>{
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
    if (samples.tankPressuresBar.isNotEmpty) {
      out['tankPressures'] = _packTankPressures(samples.tankPressuresBar);
    }
    return out;
  }

  /// Decode column blobs back into a [SampleSet].
  static SampleSet decode({
    required Map<String, Uint8List> blobs,
    required String diveId,
    required int sampleCount,
    required int sampleIntervalMs,
  }) {
    final tankBlob = blobs['tankPressures'];
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
      tankPressuresBar: tankBlob == null
          ? const []
          : _unpackTankPressures(tankBlob, sampleCount),
    );
  }

  // Tank-pressure blob layout (all big-endian for portability):
  //   uint8  numTanks
  //   for each tank:
  //     uint32 packedLen
  //     bytes  ColumnPacker.packFloat32(channel)
  static Uint8List _packTankPressures(List<Float32List> channels) {
    final packed = channels.map(ColumnPacker.packFloat32).toList();
    var totalLen = 1;
    for (final p in packed) {
      totalLen += 4 + p.length;
    }
    final out = Uint8List(totalLen);
    final view = ByteData.sublistView(out);
    out[0] = channels.length;
    var offset = 1;
    for (final p in packed) {
      view.setUint32(offset, p.length, Endian.big);
      offset += 4;
      out.setRange(offset, offset + p.length, p);
      offset += p.length;
    }
    return out;
  }

  static List<Float32List> _unpackTankPressures(Uint8List blob, int count) {
    if (blob.isEmpty) return const [];
    final n = blob[0];
    if (n == 0) return const [];
    final view = ByteData.sublistView(blob);
    final out = <Float32List>[];
    var offset = 1;
    for (var i = 0; i < n; i++) {
      final len = view.getUint32(offset, Endian.big);
      offset += 4;
      final slice = Uint8List.sublistView(blob, offset, offset + len);
      out.add(ColumnPacker.unpackFloat32(slice, count));
      offset += len;
    }
    return out;
  }

  /// Decode only the depth column (for lightweight profile rendering).
  static Float32List decodeDepth(Uint8List blob, int sampleCount) =>
      ColumnPacker.unpackFloat32(blob, sampleCount);

  /// Decode only the PPO2 column.
  static Float32List decodePpo2(Uint8List blob, int sampleCount) =>
      ColumnPacker.unpackFloat32(blob, sampleCount);
}
