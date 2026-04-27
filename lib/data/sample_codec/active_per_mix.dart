import 'dart:typed_data';

/// Computes seconds-active per gas-mix index for a dive.
///
/// Counts how many samples in [gasMixIndexes] reference each mix index,
/// then multiplies by [sampleIntervalMs] / 1000.
///
/// [gasMixIndexes] is the **already-unpacked** per-sample mix index byte
/// array — pass `ColumnPacker.unpackUint8(blob, sampleCount)` to convert
/// from the gzipped on-disk representation.
Map<int, int> activeSecondsPerMix({
  required Uint8List gasMixIndexes,
  required int sampleCount,
  required int sampleIntervalMs,
}) {
  if (sampleCount == 0) return const {};
  final counts = <int, int>{};
  final n = sampleCount < gasMixIndexes.length
      ? sampleCount
      : gasMixIndexes.length;
  for (var i = 0; i < n; i++) {
    final idx = gasMixIndexes[i];
    counts[idx] = (counts[idx] ?? 0) + 1;
  }
  final secondsPerSample = sampleIntervalMs ~/ 1000;
  return {for (final e in counts.entries) e.key: e.value * secondsPerSample};
}
