import 'dart:typed_data';

import 'package:ccrlogger/analysis/merge/merged_sample_builder.dart';
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/models/sample_set.dart';
import 'package:flutter_test/flutter_test.dart';

Dive d({
  required String id,
  required int start,
  required int end,
  int maxDepthMm = 30000,
  String gasMixesJson = '[{"o2":21,"he":0,"dil":false}]',
}) =>
    Dive(
      id: id,
      dcSerial: 1,
      dcDiveNumber: 1,
      startTime: start,
      endTime: end,
      durationSeconds: end - start,
      maxDepthMm: maxDepthMm,
      diveMode: 0,
      decoModel: 0,
      atmosphericPressureMbar: 1013,
      waterDensity: 1030,
      logVersion: 1,
      dcModel: 0,
      sampleIntervalMs: 10000,
      gasMixesJson: gasMixesJson,
      rawBlob: Uint8List(0),
      parserVersion: 1,
      importedAt: 0,
    );

SampleSet samples({
  required String diveId,
  required int count,
  double depth = 20.0,
  int gasIdx = 0,
}) =>
    SampleSet(
      diveId: diveId,
      sampleCount: count,
      sampleIntervalMs: 10000,
      depthMeters: Float32List.fromList(List.filled(count, depth)),
      temperatureCelsius: Float32List.fromList(List.filled(count, 15.0)),
      ppo2Bar: Float32List.fromList(List.filled(count, 1.2)),
      cellMv0: Float32List.fromList(List.filled(count, 50.0)),
      cellMv1: Float32List.fromList(List.filled(count, 50.0)),
      cellMv2: Float32List.fromList(List.filled(count, 50.0)),
      setpointBar: Float32List.fromList(List.filled(count, 1.2)),
      cns: Float32List.fromList(List.filled(count, 0.05)),
      decoStopDepthMeters: Float32List.fromList(List.filled(count, 0.0)),
      decoTimeSeconds: Int32List.fromList(List.filled(count, 0)),
      ttsSeconds: Int32List.fromList(List.filled(count, 0)),
      gasMixIndex: Uint8List.fromList(List.filled(count, gasIdx)),
      statusFlags: Uint8List.fromList(List.filled(count, 0)),
    );

void main() {
  test('stitches two dives with a flat surface gap between them', () {
    final a = d(id: 'a', start: 0, end: 1000, maxDepthMm: 30000);
    final b = d(id: 'b', start: 1300, end: 2300, maxDepthMm: 42000);
    final res = buildMergedDive(mergedId: 'grp', members: [
      (dive: a, samples: samples(diveId: 'a', count: 100, depth: 20.0)),
      (dive: b, samples: samples(diveId: 'b', count: 100, depth: 30.0)),
    ]);

    expect(res.samples.sampleCount, 100 + 30 + 100);
    expect(res.samples.diveId, 'grp');
    expect(res.samples.depthMeters[110], 0.0);
    expect(res.samples.ppo2Bar[110].isNaN, isTrue);
    expect(res.samples.depthMeters[150], 30.0);

    expect(res.dive.id, 'grp');
    expect(res.dive.maxDepthMm, 42000);
    expect(res.dive.durationSeconds, 1000 + 1000);
    expect(res.dive.startTime, 0);
    expect(res.dive.endTime, 2300);
  });

  test('merges gas-mix lists and remaps gasMixIndex', () {
    final a = d(
        id: 'a',
        start: 0,
        end: 1000,
        gasMixesJson: '[{"o2":21,"he":0,"dil":false}]');
    final b = d(
        id: 'b',
        start: 1300,
        end: 2300,
        gasMixesJson:
            '[{"o2":18,"he":45,"dil":true},{"o2":21,"he":0,"dil":false}]');
    final res = buildMergedDive(mergedId: 'grp', members: [
      (dive: a, samples: samples(diveId: 'a', count: 10, gasIdx: 0)),
      (dive: b, samples: samples(diveId: 'b', count: 10, gasIdx: 0)),
    ]);

    expect(res.dive.gasMixesJson.contains('"o2":18'), isTrue);
    // B's gas index 0 (18/45) remaps to 1; first B sample is at 10 + gap(30) = 40.
    expect(res.samples.gasMixIndex[40], 1);
  });

  test('throws on mismatched sample intervals', () {
    final a = d(id: 'a', start: 0, end: 100);
    final b = d(id: 'b', start: 200, end: 300);
    final sb = SampleSet(
      diveId: 'b',
      sampleCount: 10,
      sampleIntervalMs: 4000,
      depthMeters: Float32List(10),
      temperatureCelsius: Float32List(10),
      ppo2Bar: Float32List(10),
      cellMv0: Float32List(10),
      cellMv1: Float32List(10),
      cellMv2: Float32List(10),
      setpointBar: Float32List(10),
      cns: Float32List(10),
      decoStopDepthMeters: Float32List(10),
      decoTimeSeconds: Int32List(10),
      ttsSeconds: Int32List(10),
      gasMixIndex: Uint8List(10),
      statusFlags: Uint8List(10),
    );
    expect(
      () => buildMergedDive(mergedId: 'g', members: [
        (dive: a, samples: samples(diveId: 'a', count: 10)),
        (dive: b, samples: sb),
      ]),
      throwsArgumentError,
    );
  });

  test('three members with two different gaps stitch in order', () {
    // A: 0..1000 (100 samples). Gap 200s -> 20 samples.
    // B: 1200..2200 (100 samples). Gap 500s -> 50 samples.
    // C: 2700..3700 (100 samples). Passed out of order to check sorting.
    final a = d(id: 'a', start: 0, end: 1000);
    final b = d(id: 'b', start: 1200, end: 2200);
    final c = d(id: 'c', start: 2700, end: 3700);
    final res = buildMergedDive(mergedId: 'grp', members: [
      (dive: c, samples: samples(diveId: 'c', count: 100, depth: 12.0)),
      (dive: a, samples: samples(diveId: 'a', count: 100, depth: 10.0)),
      (dive: b, samples: samples(diveId: 'b', count: 100, depth: 11.0)),
    ]);

    expect(res.samples.sampleCount, 100 + 20 + 100 + 50 + 100);
    // First gap block (indices 100..119) is surface.
    expect(res.samples.depthMeters[110], 0.0);
    // B segment (after A=100 + gap=20) starts at 120.
    expect(res.samples.depthMeters[120], 11.0);
    // Second gap block (after 120+100=220, length 50) is surface.
    expect(res.samples.depthMeters[250], 0.0);
    // C segment starts at 220+50=270.
    expect(res.samples.depthMeters[270], 12.0);
    expect(res.dive.startTime, 0);
    expect(res.dive.endTime, 3700);
    expect(res.dive.durationSeconds, 1000 * 3);
  });

  test('overlapping members clamp the gap to zero (no negative block)', () {
    // B starts before A ends (overlap) — builder must not produce a
    // negative-length surface block. (Guardrails reject this upstream, but
    // the builder defends independently.)
    final a = d(id: 'a', start: 0, end: 1000);
    final b = d(id: 'b', start: 500, end: 1500);
    final res = buildMergedDive(mergedId: 'grp', members: [
      (dive: a, samples: samples(diveId: 'a', count: 100)),
      (dive: b, samples: samples(diveId: 'b', count: 100)),
    ]);
    // Gap clamped to 0 -> total is just the two segments.
    expect(res.samples.sampleCount, 200);
  });
}
