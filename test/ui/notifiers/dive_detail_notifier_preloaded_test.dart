import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:subsurface_core/data/models/sample_set.dart';
import 'package:ccrlogger/ui/notifiers/dive_detail_notifier.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

SampleSet fakeSamples(String id) => SampleSet(
      diveId: id,
      sampleCount: 2,
      sampleIntervalMs: 10000,
      depthMeters: Float32List.fromList([1, 2]),
      temperatureCelsius: Float32List(2),
      ppo2Bar: Float32List(2),
      cellMv0: Float32List(2),
      cellMv1: Float32List(2),
      cellMv2: Float32List(2),
      setpointBar: Float32List(2),
      cns: Float32List(2),
      decoStopDepthMeters: Float32List(2),
      decoTimeSeconds: Int32List(2),
      ttsSeconds: Int32List(2),
      gasMixIndex: Uint8List(2),
      statusFlags: Uint8List(2),
    );

Dive vDive(String id) => Dive(
      id: id,
      dcSerial: 1,
      dcDiveNumber: 1,
      startTime: 0,
      endTime: 20,
      durationSeconds: 20,
      maxDepthMm: 2000,
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
  test('preloadedSamples are used without hitting the DAO', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = (await openDiveDaoForTest(db)).dao; // empty DB -> getSamples null
    final pre = fakeSamples('grp');
    final n = DiveDetailNotifier(
      dive: vDive('grp'),
      dao: dao,
      preloadedSamples: pre,
    );
    await n.loadSamples();
    expect(n.samples, same(pre));
  });
}
