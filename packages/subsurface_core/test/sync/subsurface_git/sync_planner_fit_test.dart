// Pins the writer rule of phase 2 for Garmin FIT dives (dc_family -1): the
// Shearwater-only writer never pushes one as a new dive, and merges only
// CCRLog's own lines into a dive Subsurface Cloud already has.

@TestOn('mac-os || linux || windows')
library;

import 'dart:typed_data';

import 'package:subsurface_core/data/models/annotation.dart';
import 'package:subsurface_core/data/models/sample_set.dart';
import 'package:subsurface_core/sync/subsurface_git/remote_snapshot.dart';
import 'package:subsurface_core/sync/subsurface_git/sync_inputs.dart';
import 'package:subsurface_core/sync/subsurface_git/sync_planner.dart';
import 'package:subsurface_core/subsurface_core.dart' show kFitDcFamily;
import 'package:test/test.dart';

const _diveId = 'aaaaaaaa-1111-2222-3333-444444444444';
const _serial = 1000000001;
const _start = 1692262319; // 2023-08-17T08:51:59Z
const _folder = '2023/08/17-Thu-08=51=59';

/// A Garmin Descent Mk1 dive on Subsurface Cloud, in the form Subsurface's
/// git writer gives one (no `SP change` events: Garmin logs none here).
Map<String, String> _garminRepo() => {
      '00-Subsurface': 'version 3\n'
          'divecomputerid "Garmin Descent Mk1" deviceid=5c1e77a0 '
          'serial="1000000001"\n',
      '$_folder/Dive-9': 'duration 1:00 min\n'
          'rating 2\n'
          'divemaster ""\n'
          'buddy "Sam"\n'
          'notes "Written in Subsurface"\n',
      '$_folder/Divecomputer': 'model "Garmin Descent Mk1"\n'
          'deviceid 5c1e77a0\n'
          'dctype CCR\n'
          'maxdepth 6.0m\n'
          'keyvalue "Serial" "1000000001"\n'
          '  0:00 0.0m 20.0°C\n'
          '  0:10 3.0m\n'
          '  0:20 6.0m\n',
    };

CcrlogDiveBundle _garminBundle({DiveAnnotation? annotation}) {
  const n = 6;
  final samples = SampleSet(
    diveId: _diveId,
    sampleCount: n,
    sampleIntervalMs: 10000,
    depthMeters: Float32List.fromList(List.generate(n, (i) => i.toDouble())),
    temperatureCelsius: Float32List.fromList(List.filled(n, 20.0)),
    ppo2Bar: Float32List(n),
    cellMv0: Float32List(n),
    cellMv1: Float32List(n),
    cellMv2: Float32List(n),
    setpointBar: Float32List(n),
    cns: Float32List(n),
    decoStopDepthMeters: Float32List(n),
    decoTimeSeconds: Int32List(n),
    ttsSeconds: Int32List(n),
    gasMixIndex: Uint8List(n),
    statusFlags: Uint8List(n),
  );
  return CcrlogDiveBundle(
    dive: SubsurfaceDiveInput(
      id: _diveId,
      dcSerial: _serial,
      dcVendor: 'Garmin',
      dcProduct: 'Descent Mk1',
      dcFamily: kFitDcFamily,
      dcDiveNumber: 0,
      startTime: _start,
      durationSeconds: 60,
      maxDepthMm: 6000,
      diveMode: 0,
      gfLow: 50,
      gfHigh: 80,
      atmosphericPressureMbar: 1013,
      waterDensity: 1000,
      logVersion: 0,
      dcModel: 0,
      dcFirmware: null,
      configuredStackSeconds: null,
      stackRemainingAtStartSeconds: null,
      stackRemainingAtEndSeconds: null,
    ),
    samples: samples,
    annotation: annotation,
    gasMixes: const [],
    tanks: const [],
    cylindersByMixIndex: const {},
    userDiveComputers: const [
      SubsurfaceDiveComputerInput(
        serial: _serial,
        model: 0,
        dcVendor: 'Garmin',
        dcFamily: kFitDcFamily,
      ),
    ],
  );
}

SyncPlan _planOn(Map<String, String> files, List<CcrlogDiveBundle> bundles) {
  final snap = RemoteSnapshot.fromFiles(files);
  return SyncPlanner().plan(
    ccrlogDives: bundles,
    existingDivesBySerialAndStart: snap.existingDivesBySerialAndStart,
    existingMaxDiveNumber: snap.existingMaxDiveNumber,
    existingTopLevel: snap.existingTopLevel,
    existingSites: snap.existingSites,
  );
}

void main() {
  test('a never-pushed FIT dive is left out and counted', () {
    final plan = _planOn(const {}, [_garminBundle()]);

    expect(plan.filesToWrite, isEmpty);
    expect(plan.diveIdsPlanned, isEmpty);
    expect(plan.stats.newDives, 0);
    expect(plan.stats.updatedDives, 0);
    expect(plan.stats.otherBrandDives, 1);
  });

  test('a FIT dive matching a remote dive gets its notes merged, its '
      'Divecomputer file untouched, no setpoint injected', () {
    final files = _garminRepo();
    final now = DateTime.utc(2026, 11, 17);
    final plan = _planOn(files, [
      _garminBundle(
        annotation: DiveAnnotation(
          diveId: _diveId,
          notes: 'Cells checked after the dive',
          buddies: const ['Sam', 'Robin'],
          rating: 2,
          createdAt: now,
          updatedAt: now,
        ),
      ),
    ]);
    final after = {...files, ...plan.filesToWrite};

    expect(plan.filesToWrite.keys, isNot(contains('$_folder/Divecomputer')));
    expect(after['$_folder/Divecomputer'], files['$_folder/Divecomputer']);
    expect(after['$_folder/Divecomputer'], isNot(contains('SP change')));
    final diveText = plan.filesToWrite['$_folder/Dive-9']!;
    expect(diveText, contains('notes "Cells checked after the dive"'));
    expect(diveText, contains('buddy "Sam, Robin"'));
    expect(diveText, isNot(contains('Written in Subsurface')));
    expect(diveText, isNot(contains('SP change')));
    expect(after['00-Subsurface'], files['00-Subsurface']);
    expect(plan.stats.updatedDives, 1);
    expect(plan.stats.newDives, 0);
    expect(plan.stats.otherBrandDives, 0);
    expect(plan.diveIdsPlanned, [_diveId]);
  });
}
