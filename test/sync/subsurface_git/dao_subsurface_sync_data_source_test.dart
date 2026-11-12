// Adapter tests for DaoSubsurfaceSyncDataSource — wires the real DAOs
// (PowerSync + Drift backed) to the orchestrator's
// SubsurfaceSyncDataSource seam. These tests boot real PowerSync via
// the shared `openPowerSyncForTest` helper, seed a single dive, and
// verify each delegated method round-trips.
//
// We don't re-test deep DAO behaviour here — the DAOs each have their
// own dedicated test suites. The point is just that the adapter calls
// the right method on the right DAO with the right arguments.

@TestOn('mac-os || linux || windows')
library;

import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart' hide Dive, DiveAnnotation;
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:subsurface_core/data/models/annotation.dart';
import 'package:subsurface_core/data/models/dive.dart';
import 'package:subsurface_core/data/models/sample_set.dart';
import 'package:subsurface_core/shearwater/parser/constants.dart' show DiveMode, DecoModel;
import 'package:subsurface_core/shearwater/parser/dive_converter.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart' show ShearwaterModel;
import 'package:ccrlogger/sync/subsurface_git/dao_subsurface_sync_data_source.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

const _diveId = 'aaaaaaaa-1111-2222-3333-444444444444';
const _ownerId = 'test-user';

ConvertedDive _convertedDive() {
  // Minimal but realistic shape. Matches what the converter produces in
  // production; the importer pipeline expects gasMixes non-empty.
  return ConvertedDive(
    dive: Dive(
      id: _diveId,
      dcSerial: 0xb89641e4,
      dcDiveNumber: 705,
      startTime: DateTime.fromMillisecondsSinceEpoch(1776611925 * 1000,
          isUtc: true),
      endTime:
          DateTime.fromMillisecondsSinceEpoch((1776611925 + 3450) * 1000,
              isUtc: true),
      duration: const Duration(seconds: 3450),
      maxDepthMeters: 18.0,
      diveMode: DiveMode.cc,
      decoModel: DecoModel.gf,
      gfLow: 50,
      gfHigh: 95,
      atmosphericPressureMbar: 1013,
      waterDensityKgM3: 1025,
      logVersion: 17,
      dcModel: ShearwaterModel.petrel3,
      sampleIntervalMs: 10000,
      gasMixes: [
        DiveGasMix(oxygenPercent: 18, heliumPercent: 23, isDiluent: true),
      ],
      configuredStackSeconds: 25200,
      stackRemainingAtStartSeconds: 10847,
      stackRemainingAtEndSeconds: 7347,
    ),
    samples: _smallSampleSet(),
  );
}

SampleSet _smallSampleSet() {
  const n = 6;
  return SampleSet(
    diveId: _diveId,
    sampleCount: n,
    sampleIntervalMs: 10000,
    depthMeters: Float32List.fromList(
      List.generate(n, (i) => 5.0 + i.toDouble()),
    ),
    temperatureCelsius: Float32List.fromList(List.filled(n, 12.0)),
    ppo2Bar: Float32List.fromList(List.filled(n, 1.0)),
    cellMv0: Float32List.fromList(List.filled(n, 0.95)),
    cellMv1: Float32List.fromList(List.filled(n, 0.97)),
    cellMv2: Float32List.fromList(List.filled(n, 0.96)),
    setpointBar: Float32List.fromList(List.filled(n, 1.0)),
    cns: Float32List.fromList(List.filled(n, 0.0)),
    decoStopDepthMeters: Float32List(n),
    decoTimeSeconds: Int32List(n),
    ttsSeconds: Int32List.fromList(List.filled(n, 60)),
    gasMixIndex: Uint8List(n),
    statusFlags: Uint8List(n),
  );
}

class _Rig {
  final AppDatabase drift;
  final DaoSubsurfaceSyncDataSource adapter;
  final DiveDao diveDao;
  final DiveAnnotationsDao annotationsDao;
  final EquipmentDao equipmentDao;
  _Rig({
    required this.drift,
    required this.adapter,
    required this.diveDao,
    required this.annotationsDao,
    required this.equipmentDao,
  });
}

Future<_Rig> _buildRig() async {
  final drift = AppDatabase(NativeDatabase.memory());
  addTearDown(() async => drift.close());
  final ps = await openPowerSyncForTest();
  final session = FakeSessionSource()..setUserId(_ownerId);
  final diveDao = DiveDao(drift, ps, session);
  final annotationsDao = DiveAnnotationsDao(ps, session);
  final equipmentDao = EquipmentDao(drift, ps, session);
  final adapter = DaoSubsurfaceSyncDataSource(
    diveDao: diveDao,
    annotationsDao: annotationsDao,
    equipmentDao: equipmentDao,
  );
  return _Rig(
    drift: drift,
    adapter: adapter,
    diveDao: diveDao,
    annotationsDao: annotationsDao,
    equipmentDao: equipmentDao,
  );
}

Future<void> _seedOneDive(_Rig r) async {
  await r.diveDao.importDive(
    converted: _convertedDive(),
    rawBlob: Uint8List(0),
    parserVersion: 1,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('getAllDives returns the seeded dive', () async {
    final r = await _buildRig();
    await _seedOneDive(r);
    final dives = await r.adapter.getAllDives();
    expect(dives, hasLength(1));
    expect(dives.single.id, _diveId);
  });

  test('getSamples returns the seeded sample set', () async {
    final r = await _buildRig();
    await _seedOneDive(r);
    final samples = await r.adapter.getSamples(_diveId);
    expect(samples, isNotNull);
    expect(samples!.sampleCount, 6);
    // One spot-check that the codec round-trip survived the adapter.
    expect(samples.depthMeters[5], closeTo(10.0, 1e-6));
  });

  test('getAnnotation returns null when no annotation exists, then '
      'returns the upserted annotation', () async {
    final r = await _buildRig();
    await _seedOneDive(r);

    expect(await r.adapter.getAnnotation(_diveId), isNull);

    await r.annotationsDao.upsert(DiveAnnotation(
      diveId: _diveId,
      notes: 'Test trim dive',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1),
    ));

    final fetched = await r.adapter.getAnnotation(_diveId);
    expect(fetched, isNotNull);
    expect(fetched!.notes, 'Test trim dive');
  });

  test('cylindersByMixIndex resolves ids to full Cylinder rows '
      'and skips unmapped indexes', () async {
    final r = await _buildRig();
    await _seedOneDive(r);

    final cylId = await r.equipmentDao.addCylinder(
      label: 'Diluent',
      role: 'diluent',
      volumeLiters: 3.0,
      workingPressureBar: 232,
    );
    await r.equipmentDao.setDiveCylinder(_diveId, 0, cylId);
    // Index 1 is mapped to null — should be skipped by the adapter.
    await r.equipmentDao.setDiveCylinder(_diveId, 1, null);

    final mapping = await r.adapter.cylindersByMixIndex(_diveId);
    expect(mapping.keys, [0]);
    expect(mapping[0]!.label, 'Diluent');
    expect(mapping[0]!.id, cylId);
  });

  test('listAllDiveComputers returns every registered computer', () async {
    final r = await _buildRig();
    await r.equipmentDao.upsertDiveComputer(
      serial: 0xb89641e4,
      model: 3,
      firmwareVersion: 0xa3,
    );
    await r.equipmentDao.upsertDiveComputer(
      serial: 0x12345678,
      model: 2,
    );
    final computers = await r.adapter.listAllDiveComputers();
    expect(computers, hasLength(2));
    expect(
      computers.map((c) => c.serial).toSet(),
      {0xb89641e4, 0x12345678},
    );
  });

  test('markSubsurfaceUploaded stamps the dive and is reflected by '
      'lastSubsurfaceUploadedAt', () async {
    final r = await _buildRig();
    await _seedOneDive(r);
    expect(await r.diveDao.lastSubsurfaceUploadedAt(), isNull);

    await r.adapter.markSubsurfaceUploaded([_diveId], 1700000000);
    expect(await r.diveDao.lastSubsurfaceUploadedAt(), 1700000000);

    final dive = await r.diveDao.getDive(_diveId);
    expect(dive!.subsurfaceUploadedAt, 1700000000);
  });
}
