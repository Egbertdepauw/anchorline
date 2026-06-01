import 'dart:typed_data';

import 'package:ccrlogger/analysis/merge/merge_validator.dart';
import 'package:ccrlogger/data/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal Drift `Dive` for tests. startTime/endTime are epoch SECONDS.
Dive d({
  required String id,
  required int serial,
  required int start,
  required int end,
}) =>
    Dive(
      id: id,
      dcSerial: serial,
      dcDiveNumber: 1,
      startTime: start,
      endTime: end,
      durationSeconds: end - start,
      maxDepthMm: 30000,
      diveMode: 0,
      decoModel: 0,
      atmosphericPressureMbar: 1013,
      waterDensity: 1030,
      logVersion: 1,
      dcModel: 0,
      sampleIntervalMs: 10000,
      gasMixesJson: '[]',
      rawBlob: Uint8List(0),
      parserVersion: 1,
      importedAt: 0,
    );

void main() {
  final a = d(id: 'a', serial: 1, start: 0, end: 3600);
  final b = d(id: 'b', serial: 1, start: 3600 + 1800, end: 9000);
  final c = d(id: 'c', serial: 1, start: 9000 + 1800, end: 14400);
  final all = [a, b, c];

  test('valid adjacent same-DC pair passes', () {
    expect(validateMerge(selected: [a, b], allDives: all).canMerge, isTrue);
  });

  test('fewer than two is rejected', () {
    expect(validateMerge(selected: [a], allDives: all).canMerge, isFalse);
  });

  test('different dive computers rejected', () {
    final other = d(id: 'x', serial: 2, start: 4000, end: 5000);
    expect(
        validateMerge(selected: [a, other], allDives: [a, other]).canMerge,
        isFalse);
  });

  test('non-adjacent selection (a and c skipping b) rejected', () {
    expect(validateMerge(selected: [a, c], allDives: all).canMerge, isFalse);
  });

  test('surface gap over 1h rejected', () {
    final far = d(id: 'far', serial: 1, start: 3600 + 3601, end: 9000);
    expect(
        validateMerge(selected: [a, far], allDives: [a, far]).canMerge, isFalse);
  });

  test('overlapping dives rejected', () {
    final overlap = d(id: 'ov', serial: 1, start: 1800, end: 5000);
    expect(validateMerge(selected: [a, overlap], allDives: [a, overlap]).canMerge,
        isFalse);
  });
}
