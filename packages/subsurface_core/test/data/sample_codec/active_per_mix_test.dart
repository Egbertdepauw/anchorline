import 'dart:typed_data';

import 'package:subsurface_core/data/sample_codec/active_per_mix.dart';
import 'package:test/test.dart';

void main() {
  test('counts samples per mix index and converts to seconds', () {
    // Indexes: [0, 0, 0, 1, 1, 2] = 6 samples, sampleIntervalMs=10000 (10s).
    // Expect: {0: 30, 1: 20, 2: 10}.
    final raw = Uint8List.fromList([0, 0, 0, 1, 1, 2]);
    final out = activeSecondsPerMix(
      gasMixIndexes: raw,
      sampleCount: 6,
      sampleIntervalMs: 10000,
    );
    expect(out, {0: 30, 1: 20, 2: 10});
  });

  test('handles a single-mix dive', () {
    final raw = Uint8List.fromList(List.filled(120, 0));
    final out = activeSecondsPerMix(
      gasMixIndexes: raw,
      sampleCount: 120,
      sampleIntervalMs: 5000,
    );
    expect(out, {0: 600});
  });

  test('returns empty map for zero samples', () {
    final out = activeSecondsPerMix(
      gasMixIndexes: Uint8List(0),
      sampleCount: 0,
      sampleIntervalMs: 10000,
    );
    expect(out, isEmpty);
  });
}
