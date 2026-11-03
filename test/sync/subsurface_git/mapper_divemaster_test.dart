import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart' hide DiveAnnotation;
import 'package:subsurface_core/data/models/annotation.dart';
import 'package:subsurface_core/data/models/sample_set.dart';
import 'package:ccrlogger/sync/subsurface_git/format/subsurface_format.dart';
import 'package:ccrlogger/sync/subsurface_git/format/subsurface_serializer.dart';
import 'package:ccrlogger/sync/subsurface_git/mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mapDive emits divemaster from annotation when set', () {
    final mapper = CcrlogToSubsurfaceMapper();
    final ann = DiveAnnotation(
      diveId: 'dive-id-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      divemaster: 'Wendy De Joode',
      createdAt: DateTime.utc(2026, 5, 12),
      updatedAt: DateTime.utc(2026, 5, 12),
    );
    final mapped = mapper.mapDive(
      dive: _testDive(),
      samples: _testSamples(),
      annotation: ann,
      gasMixes: const [],
      tanks: const [],
      cylindersByMixIndex: const {},
      nextSubsurfaceDiveNumber: 1,
    );
    final text = serializeSubsurfaceFile(SubsurfaceFile(lines: mapped.diveLines));
    expect(text, contains('divemaster "Wendy De Joode"'));
  });

  test('mapDive emits empty divemaster when annotation field is null', () {
    final mapper = CcrlogToSubsurfaceMapper();
    final ann = DiveAnnotation(
      diveId: 'dive-id-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      createdAt: DateTime.utc(2026, 5, 12),
      updatedAt: DateTime.utc(2026, 5, 12),
    );
    final mapped = mapper.mapDive(
      dive: _testDive(),
      samples: _testSamples(),
      annotation: ann,
      gasMixes: const [],
      tanks: const [],
      cylindersByMixIndex: const {},
      nextSubsurfaceDiveNumber: 1,
    );
    final text = serializeSubsurfaceFile(SubsurfaceFile(lines: mapped.diveLines));
    expect(text, contains('divemaster ""'));
  });
}

Dive _testDive() => Dive(
      id: 'dive-id-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      dcSerial: 0xb89641e4,
      dcDiveNumber: 1,
      startTime: 1776611925,
      endTime: 1776611925 + 3450,
      utcOffsetMinutes: null,
      durationSeconds: 3450,
      maxDepthMm: 18000,
      diveMode: 0, // cc
      decoModel: 0,
      gfLow: 50,
      gfHigh: 95,
      atmosphericPressureMbar: 1013,
      waterDensity: 1025,
      logVersion: 17,
      dcModel: 3,
      dcFirmware: 0xa3,
      sampleIntervalMs: 10000,
      gasMixesJson: '',
      tanksJson: null,
      configuredStackSeconds: 25200,
      stackRemainingAtStartSeconds: 10847,
      stackRemainingAtEndSeconds: 7347,
      rawBlob: Uint8List(0),
      parserVersion: 1,
      importedAt: 1776591525,
    );

SampleSet _testSamples() => SampleSet(
      diveId: 'dive-id-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      sampleCount: 0,
      sampleIntervalMs: 10000,
      depthMeters: Float32List(0),
      temperatureCelsius: Float32List(0),
      ppo2Bar: Float32List(0),
      cellMv0: Float32List(0),
      cellMv1: Float32List(0),
      cellMv2: Float32List(0),
      setpointBar: Float32List(0),
      cns: Float32List(0),
      decoStopDepthMeters: Float32List(0),
      decoTimeSeconds: Int32List(0),
      ttsSeconds: Int32List(0),
      gasMixIndex: Uint8List(0),
      statusFlags: Uint8List(0),
    );
