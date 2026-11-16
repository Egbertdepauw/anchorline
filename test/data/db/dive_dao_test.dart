import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_attachments_dao.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/dive_merge_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:subsurface_core/data/models/dive.dart' as model;
import 'package:subsurface_core/data/models/sample_set.dart';
import 'package:ccrlogger/data/models/dive_attachment.dart';
import 'package:powersync/powersync.dart';
import 'package:subsurface_core/shearwater/parser/dive_converter.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

AppDatabase _createInMemoryDb() {
  return AppDatabase(NativeDatabase.memory());
}

ConvertedDive _convertFixture(int diveNumber) {
  final data =
      File('test/fixtures/dives/dive_$diveNumber.bin').readAsBytesSync();
  final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
  final parsed = parser.parse(data);
  return DiveConverter.convert(
    parsed: parsed,
    dcSerial: 0xB89641E4,
    dcDiveNumber: diveNumber,
    dcModel: ShearwaterModel.petrel3,
  );
}

/// Returns a copy of [dive] with [sensorCalibration] substituted in.
/// Lets us assert deterministic round-trip semantics without depending
/// on whatever the parser happens to read out of a fixture binary.
model.Dive _diveWithCalibration(
    model.Dive dive, List<double> sensorCalibration) {
  return model.Dive(
    id: dive.id,
    dcSerial: dive.dcSerial,
    dcDiveNumber: dive.dcDiveNumber,
    startTime: dive.startTime,
    endTime: dive.endTime,
    utcOffsetMinutes: dive.utcOffsetMinutes,
    duration: dive.duration,
    maxDepthMeters: dive.maxDepthMeters,
    diveMode: dive.diveMode,
    decoModel: dive.decoModel,
    gfLow: dive.gfLow,
    gfHigh: dive.gfHigh,
    atmosphericPressureMbar: dive.atmosphericPressureMbar,
    waterDensityKgM3: dive.waterDensityKgM3,
    logVersion: dive.logVersion,
    dcModel: dive.dcModel,
    gasMixes: dive.gasMixes,
    tanks: dive.tanks,
    sampleIntervalMs: dive.sampleIntervalMs,
    sensorCalibration: sensorCalibration,
    configuredStackSeconds: dive.configuredStackSeconds,
    stackRemainingAtStartSeconds: dive.stackRemainingAtStartSeconds,
    stackRemainingAtEndSeconds: dive.stackRemainingAtEndSeconds,
  );
}

/// Rebuilds [c] with the given brand fields, per-cell ppO2 channels and
/// events substituted in.
ConvertedDive _withPhase1Data(
  ConvertedDive c, {
  String? vendor,
  String? product,
  int? family,
  int? modelCode,
  List<Float32List> cells = const [],
  List<DiveEvent> events = const [],
}) {
  final d = c.dive;
  final s = c.samples;
  return ConvertedDive(
    dive: model.Dive(
      id: d.id,
      dcSerial: d.dcSerial,
      dcDiveNumber: d.dcDiveNumber,
      startTime: d.startTime,
      endTime: d.endTime,
      utcOffsetMinutes: d.utcOffsetMinutes,
      duration: d.duration,
      maxDepthMeters: d.maxDepthMeters,
      diveMode: d.diveMode,
      decoModel: d.decoModel,
      gfLow: d.gfLow,
      gfHigh: d.gfHigh,
      atmosphericPressureMbar: d.atmosphericPressureMbar,
      waterDensityKgM3: d.waterDensityKgM3,
      logVersion: d.logVersion,
      dcModel: d.dcModel,
      gasMixes: d.gasMixes,
      tanks: d.tanks,
      sampleIntervalMs: d.sampleIntervalMs,
      sensorCalibration: d.sensorCalibration,
      configuredStackSeconds: d.configuredStackSeconds,
      stackRemainingAtStartSeconds: d.stackRemainingAtStartSeconds,
      stackRemainingAtEndSeconds: d.stackRemainingAtEndSeconds,
      dcVendor: vendor,
      dcProduct: product,
      dcFamily: family,
      dcModelCode: modelCode,
    ),
    samples: SampleSet(
      diveId: s.diveId,
      sampleCount: s.sampleCount,
      sampleIntervalMs: s.sampleIntervalMs,
      depthMeters: s.depthMeters,
      temperatureCelsius: s.temperatureCelsius,
      ppo2Bar: s.ppo2Bar,
      cellMv0: s.cellMv0,
      cellMv1: s.cellMv1,
      cellMv2: s.cellMv2,
      setpointBar: s.setpointBar,
      cns: s.cns,
      decoStopDepthMeters: s.decoStopDepthMeters,
      decoTimeSeconds: s.decoTimeSeconds,
      ttsSeconds: s.ttsSeconds,
      gasMixIndex: s.gasMixIndex,
      statusFlags: s.statusFlags,
      tankPressuresBar: s.tankPressuresBar,
      cellPpo2Bar: cells,
    ),
    events: events,
  );
}

void main() {
  late AppDatabase db;
  late DiveDao dao;
  late PowerSyncDatabase openPs;
  late FakeSessionSource session;

  setUp(() async {
    db = _createInMemoryDb();
    final rig = await openDiveDaoForTest(db);
    dao = rig.dao;
    openPs = rig.ps;
    session = rig.session;
  });

  tearDown(() async {
    await db.close();
  });

  group('importDive', () {
    test('imports a dive and its samples atomically', () async {
      final converted = _convertFixture(718);
      final rawBlob =
          File('test/fixtures/dives/dive_718.bin').readAsBytesSync();

      final result = await dao.importDive(
        converted: converted,
        rawBlob: rawBlob,
        parserVersion: 1,
      );

      expect(result, ImportOutcome.inserted);
    });

    test('dedup: importing same dive twice returns unchanged', () async {
      final converted = _convertFixture(718);
      final rawBlob =
          File('test/fixtures/dives/dive_718.bin').readAsBytesSync();

      final first = await dao.importDive(
        converted: converted,
        rawBlob: rawBlob,
        parserVersion: 1,
      );
      expect(first, ImportOutcome.inserted);

      final second = await dao.importDive(
        converted: converted,
        rawBlob: rawBlob,
        parserVersion: 1,
      );
      expect(second, ImportOutcome.unchanged);
    });

    test('imports multiple different dives', () async {
      for (final num in [711, 712, 718]) {
        final converted = _convertFixture(num);
        final rawBlob =
            File('test/fixtures/dives/dive_$num.bin').readAsBytesSync();
        final result = await dao.importDive(
          converted: converted,
          rawBlob: rawBlob,
          parserVersion: 1,
        );
        expect(result, ImportOutcome.inserted, reason: 'Dive $num should import successfully');
      }
    });

    test('persists per-cell sensor calibration through the DAO', () async {
      // Substitute a known-good calibration on top of fixture 718 so the
      // round-trip assertion is deterministic regardless of what value
      // the parser pulled from the binary.
      final original = _convertFixture(718);
      final calibration = [0.021, 0.022, 0.020];
      final converted = ConvertedDive(
        dive: _diveWithCalibration(original.dive, calibration),
        samples: original.samples,
      );
      final rawBlob =
          File('test/fixtures/dives/dive_718.bin').readAsBytesSync();

      await dao.importDive(
        converted: converted,
        rawBlob: rawBlob,
        parserVersion: 1,
      );

      final stored = await dao.getDive(converted.dive.id);
      expect(stored, isNotNull);
      expect(stored!.sensorCalibrationJson, isNotNull);
      final decoded = (jsonDecode(stored.sensorCalibrationJson!) as List)
          .map((v) => (v as num).toDouble())
          .toList();
      expect(decoded, equals(calibration));
    });

    test('OC-style empty calibration is persisted as null', () async {
      // Empty list (OC dives) is stored as NULL so the mapper / chart
      // fallback path is consistent with legacy rows.
      final original = _convertFixture(718);
      final converted = ConvertedDive(
        dive: _diveWithCalibration(original.dive, const <double>[]),
        samples: original.samples,
      );
      final rawBlob =
          File('test/fixtures/dives/dive_718.bin').readAsBytesSync();

      await dao.importDive(
        converted: converted,
        rawBlob: rawBlob,
        parserVersion: 1,
      );

      final stored = await dao.getDive(converted.dive.id);
      expect(stored, isNotNull);
      expect(stored!.sensorCalibrationJson, isNull);
    });
  });

  group('phase 1 columns', () {
    final raw = File('test/fixtures/dives/dive_718.bin').readAsBytesSync();

    Future<ConvertedDive> importWith({
      String? vendor,
      String? product,
      int? family,
      int? modelCode,
      List<Float32List> cells = const [],
      List<DiveEvent> events = const [],
    }) async {
      final c = _withPhase1Data(_convertFixture(718),
          vendor: vendor,
          product: product,
          family: family,
          modelCode: modelCode,
          cells: cells,
          events: events);
      await dao.importDive(converted: c, rawBlob: raw, parserVersion: 7);
      return c;
    }

    test('importDive stores the brand fields', () async {
      final c = await importWith(
          vendor: 'Garmin', product: 'Descent Mk2', family: 12, modelCode: 3);
      final d = await dao.getDive(c.dive.id);
      expect(d!.dcVendor, 'Garmin');
      expect(d.dcProduct, 'Descent Mk2');
      expect(d.dcFamily, 12);
      expect(d.dcModelCode, 3);
      expect(d.matchCandidatesJson, isNull);
    });

    test('per-cell ppO2 survives importDive → getSamples', () async {
      final n = _convertFixture(718).samples.sampleCount;
      final cells = [
        for (var c = 0; c < 3; c++)
          Float32List.fromList(List.generate(n, (i) => 0.5 + c + i / 1000)),
      ];
      final c = await importWith(cells: cells);
      final s = await dao.getSamples(c.dive.id);
      expect(s!.cellPpo2Bar.length, 3);
      for (var k = 0; k < 3; k++) {
        expect(s.cellPpo2Bar[k], equals(cells[k]));
      }
    });

    test('events survive importDive → getEvents', () async {
      final c = await importWith(events: [
        DiveEvent(timeMs: 1000, type: DiveEventType.bookmark, rawType: 5),
        DiveEvent(
            timeMs: 60000,
            type: DiveEventType.gasSwitch,
            rawType: 9,
            value: 2),
      ]);
      final ev = await dao.getEvents(c.dive.id);
      expect(ev.length, 2);
      expect(ev[0].timeMs, 1000);
      expect(ev[0].type, DiveEventType.bookmark);
      expect(ev[1].type, DiveEventType.gasSwitch);
      expect(ev[1].value, 2);
    });

    test('a dive without events or cells stores NULL blobs', () async {
      final c = await importWith();
      final row = await openPs.get(
          'SELECT cell_ppo2_blob, events_blob FROM dive_samples WHERE id = ?',
          [c.dive.id]);
      expect(row['cell_ppo2_blob'], isNull);
      expect(row['events_blob'], isNull);
      expect(await dao.getEvents(c.dive.id), isEmpty);
      expect((await dao.getSamples(c.dive.id))!.cellPpo2Bar, isEmpty);
    });

    test('the samples row carries parser_version and dc_family', () async {
      final c = await importWith(family: 12);
      final row = await openPs.get(
          'SELECT parser_version, dc_family FROM dive_samples WHERE id = ?',
          [c.dive.id]);
      expect(row['parser_version'], 7);
      expect(row['dc_family'], 12);
    });

    test('getEvents returns empty for an unknown dive', () async {
      expect(await dao.getEvents('nope'), isEmpty);
    });

    test('a corrupt events_blob reads as no events', () async {
      final c = await importWith();
      await openPs.execute(
          'UPDATE dive_samples SET events_blob = ? WHERE id = ?',
          ['not base64!', c.dive.id]);
      expect(await dao.getEvents(c.dive.id), isEmpty);
    });

    test('a corrupt cell_ppo2_blob leaves the rest of the profile', () async {
      final c = await importWith();
      await openPs.execute(
          'UPDATE dive_samples SET cell_ppo2_blob = ? WHERE id = ?',
          ['not base64!', c.dive.id]);
      final s = await dao.getSamples(c.dive.id);
      expect(s, isNotNull);
      expect(s!.depthMeters.length, s.sampleCount);
      expect(s.cellPpo2Bar, isEmpty);
    });

    test('getSamples and getEvents read a samples row written by an old build',
        () async {
      final c = _convertFixture(718);
      await dao.importDive(converted: c, rawBlob: raw, parserVersion: 1);
      // Rewrite the samples row the way a pre-phase-1 build wrote it.
      await openPs.execute(
          'UPDATE dive_samples SET cell_ppo2_blob = NULL, events_blob = NULL, '
          'parser_version = NULL, dc_family = NULL WHERE id = ?',
          [c.dive.id]);
      final s = await dao.getSamples(c.dive.id);
      expect(s, isNotNull);
      expect(s!.cellPpo2Bar, isEmpty);
      expect(await dao.getEvents(c.dive.id), isEmpty);
    });
  });

  group('queries', () {
    setUp(() async {
      // Import 3 dives for query tests
      for (final num in [711, 712, 718]) {
        final converted = _convertFixture(num);
        final rawBlob =
            File('test/fixtures/dives/dive_$num.bin').readAsBytesSync();
        await dao.importDive(
          converted: converted,
          rawBlob: rawBlob,
          parserVersion: 1,
        );
      }
    });

    test('diveExists returns true for imported dives', () async {
      final converted = _convertFixture(718);
      expect(await dao.diveExists(converted.dive.id), isTrue);
    });

    test('diveExists returns false for unknown dives', () async {
      expect(await dao.diveExists('nonexistent'), isFalse);
    });

    test('getAllDives returns all imported dives ordered by start time desc',
        () async {
      final dives = await dao.getAllDives();
      expect(dives, hasLength(3));
      // Most recent first
      for (var i = 1; i < dives.length; i++) {
        expect(dives[i].startTime, lessThanOrEqualTo(dives[i - 1].startTime));
      }
    });

    test('getSamples returns correct sample data', () async {
      final converted = _convertFixture(718);
      final samples = await dao.getSamples(converted.dive.id);

      expect(samples, isNotNull);
      expect(samples!.sampleCount, equals(converted.samples.sampleCount));
      expect(samples.depthMeters, equals(converted.samples.depthMeters));
      expect(samples.ppo2Bar, equals(converted.samples.ppo2Bar));
    });

    test('getSamples returns null for unknown dive', () async {
      final samples = await dao.getSamples('nonexistent');
      expect(samples, isNull);
    });

    test('getRawBlob returns the original binary', () async {
      final converted = _convertFixture(718);
      final originalBlob =
          File('test/fixtures/dives/dive_718.bin').readAsBytesSync();
      final stored = await dao.getRawBlob(converted.dive.id);

      expect(stored, isNotNull);
      expect(stored, equals(originalBlob));
    });
  });

  group('subsurface upload tracking', () {
    setUp(() async {
      for (final num in [711, 712, 718]) {
        final converted = _convertFixture(num);
        final rawBlob =
            File('test/fixtures/dives/dive_$num.bin').readAsBytesSync();
        await dao.importDive(
          converted: converted,
          rawBlob: rawBlob,
          parserVersion: 1,
        );
      }
    });

    test('all imports start as pending uploads', () async {
      final pending = await dao.getPendingSubsurfaceUploads();
      expect(pending, hasLength(3));
      // Ascending by start time.
      for (var i = 1; i < pending.length; i++) {
        expect(pending[i].startTime,
            greaterThanOrEqualTo(pending[i - 1].startTime));
      }
    });

    test('markSubsurfaceUploaded removes them from pending', () async {
      final marked = _convertFixture(718).dive.id;
      await dao.markSubsurfaceUploaded([marked], 1700000000);

      final pending = await dao.getPendingSubsurfaceUploads();
      expect(pending, hasLength(2));
      expect(pending.every((d) => d.id != marked), isTrue);
      // Ordering preserved.
      for (var i = 1; i < pending.length; i++) {
        expect(pending[i].startTime,
            greaterThanOrEqualTo(pending[i - 1].startTime));
      }
    });

    test('markSubsurfaceUploaded with empty list is a no-op', () async {
      await dao.markSubsurfaceUploaded(const [], 1700000000);
      final pending = await dao.getPendingSubsurfaceUploads();
      expect(pending, hasLength(3));
    });
  });

  group('soft-delete', () {
    setUp(() async {
      // The 'subsurface uploaded' group's setUp imports 711/712/718 in
      // its own scope; this group needs its own seed.
      for (final n in [711, 712, 718]) {
        final converted = _convertFixture(n);
        final raw = File('test/fixtures/dives/dive_$n.bin').readAsBytesSync();
        await dao.importDive(
          converted: converted,
          rawBlob: raw,
          parserVersion: 1,
        );
      }
    });

    test('softDeleteDive keeps an existing owner and claims an ownerless row',
        () async {
      Future<String?> ownerOf(String id) async => (await openPs
          .get('SELECT owner_id FROM dives WHERE id = ?', [id]))['owner_id']
          as String?;
      final ids = (await dao.getAllDives()).map((d) => d.id).toList();
      await openPs.execute(
          'UPDATE dives SET owner_id = ? WHERE id = ?', ['uid-a', ids[0]]);
      await openPs.execute(
          'UPDATE dives SET owner_id = ? WHERE id = ?', ['uid-a', ids[1]]);
      await openPs
          .execute('UPDATE dives SET owner_id = NULL WHERE id = ?', [ids[2]]);

      session.setUserId('uid-b');
      await dao.softDeleteDive(ids[0]);
      session.clear();
      await dao.softDeleteDive(ids[1]);
      session.setUserId('uid-b');
      await dao.softDeleteDive(ids[2]);

      expect(await ownerOf(ids[0]), 'uid-a');
      expect(await ownerOf(ids[1]), 'uid-a');
      expect(await ownerOf(ids[2]), 'uid-b');
    });

    test('softDeleteDive hides the dive from getAllDives', () async {
      final id = (await dao.getAllDives()).first.id;
      await dao.softDeleteDive(id);
      final visible = await dao.getAllDives();
      expect(visible.any((d) => d.id == id), isFalse);
      expect(visible, hasLength(2));
    });

    test('softDeleteDive also excludes from pending Subsurface uploads',
        () async {
      final id = (await dao.getAllDives()).first.id;
      final beforeCount = (await dao.getPendingSubsurfaceUploads()).length;
      await dao.softDeleteDive(id);
      final pending = await dao.getPendingSubsurfaceUploads();
      expect(pending, hasLength(beforeCount - 1));
      expect(pending.any((d) => d.id == id), isFalse);
    });

    test('getDive still returns soft-deleted rows (for the undo path)',
        () async {
      final id = (await dao.getAllDives()).first.id;
      await dao.softDeleteDive(id);
      final row = await dao.getDive(id);
      expect(row, isNotNull);
      expect(row!.deletedAt, isNotNull);
    });

    test('restoreDive clears deletedAt and re-includes the dive', () async {
      final id = (await dao.getAllDives()).first.id;
      await dao.softDeleteDive(id);
      expect((await dao.getAllDives()).any((d) => d.id == id), isFalse);
      await dao.restoreDive(id);
      final visible = await dao.getAllDives();
      expect(visible.any((d) => d.id == id), isTrue);
      expect(visible, hasLength(3));
    });
  });

  group('cascade-delete dive_bailout_carry', () {
    late DiveDao diveDao;
    late EquipmentDao equipDao;
    late PowerSyncDatabase ps;
    late String diveId;

    setUp(() async {
      // Own rig so DiveDao and EquipmentDao share ONE PowerSync handle.
      final rig = await openDiveDaoForTest(db);
      diveDao = rig.dao;
      ps = rig.ps;
      equipDao = EquipmentDao(db, rig.ps, rig.session);
      await diveDao.importDive(
        converted: _convertFixture(711),
        rawBlob: File('test/fixtures/dives/dive_711.bin').readAsBytesSync(),
        parserVersion: 1,
      );
      diveId = (await diveDao.getAllDives()).single.id;
      await equipDao.addBailoutCarry(
          diveId: diveId, cylinderId: 'cyl-a', gasMix: '50', bailoutOrder: 1);
      await equipDao.addBailoutCarry(
          diveId: diveId, cylinderId: 'cyl-b', gasMix: '100', bailoutOrder: 2);
    });

    Future<int> rawRowCount() async => (await ps.getAll(
            'SELECT id FROM dive_bailout_carry WHERE dive_id = ?', [diveId]))
        .length;

    test('softDeleteDive cascade-soft-deletes the bailout rows', () async {
      expect(await equipDao.listBailoutCarry(diveId), hasLength(2));
      await diveDao.softDeleteDive(diveId);
      // Hidden from the live list, but the rows still exist (soft delete).
      expect(await equipDao.listBailoutCarry(diveId), isEmpty);
      expect(await rawRowCount(), 2);
    });

    test('restoreDive cascade-restores the bailout rows', () async {
      await diveDao.softDeleteDive(diveId);
      expect(await equipDao.listBailoutCarry(diveId), isEmpty);
      await diveDao.restoreDive(diveId);
      expect(await equipDao.listBailoutCarry(diveId), hasLength(2));
    });

    test('restoreDive does not revive an independently-deleted cylinder',
        () async {
      // Mark cyl-b deleted at a clearly-earlier instant (as if the user removed
      // it before deleting the dive). Direct write keeps the timestamp distinct
      // and deterministic regardless of test speed.
      await ps.execute(
        'UPDATE dive_bailout_carry SET deleted_at = 1 WHERE id = ?',
        ['$diveId:cyl-b'],
      );
      await diveDao.softDeleteDive(diveId); // cascades cyl-a only
      await diveDao.restoreDive(diveId);
      final live = await equipDao.listBailoutCarry(diveId);
      expect(live.map((b) => b.cylinderId), ['cyl-a']);
    });
  });

  group('cascade-delete dive_attachments (#198)', () {
    late DiveDao diveDao;
    late DiveAttachmentsDao attDao;
    late PowerSyncDatabase ps;
    late String diveId;

    FileAttachment file(String id, String parentId) {
      final t = DateTime.now();
      return FileAttachment(
        id: id,
        parentKind: DiveAttachmentParentKind.dive,
        parentId: parentId,
        storageKey: 'attachments/test-user/$parentId/$id.jpg',
        mimeType: 'image/jpeg',
        uploadState: UploadState.uploaded,
        createdAt: t,
        updatedAt: t,
      );
    }

    LinkAttachment link(String id, String parentId) {
      final t = DateTime.now();
      return LinkAttachment(
        id: id,
        parentKind: DiveAttachmentParentKind.dive,
        parentId: parentId,
        url: 'https://example.com/$id',
        createdAt: t,
        updatedAt: t,
      );
    }

    Future<String> importFixture(int n) async {
      final converted = _convertFixture(n);
      await diveDao.importDive(
        converted: converted,
        rawBlob: File('test/fixtures/dives/dive_$n.bin').readAsBytesSync(),
        parserVersion: 1,
      );
      return converted.dive.id;
    }

    Future<int?> deletedAtOf(String table, String id) async =>
        (await ps.get('SELECT deleted_at FROM $table WHERE id = ?', [id]))[
            'deleted_at'] as int?;

    Future<List<String>> liveIds(String parentId) async =>
        (await attDao.listForDive(parentId)).map((a) => a.id).toList()..sort();

    setUp(() async {
      // Own rig so DiveDao and DiveAttachmentsDao share ONE PowerSync handle.
      final rig = await openDiveDaoForTest(db);
      diveDao = rig.dao;
      ps = rig.ps;
      attDao = DiveAttachmentsDao(rig.ps, rig.session);
      diveId = await importFixture(711);
      await attDao.insertFile(file('f1', diveId));
      await attDao.insertFile(file('f2', diveId));
      await attDao.insertLink(link('l1', diveId));
    });

    test('softDeleteDive soft-deletes its attachments with the same deleted_at',
        () async {
      await diveDao.softDeleteDive(diveId);
      expect(await attDao.listForDive(diveId), isEmpty);
      final diveDeletedAt = await deletedAtOf('dives', diveId);
      expect(diveDeletedAt, isNotNull);
      for (final id in ['f1', 'f2', 'l1']) {
        expect(await deletedAtOf('dive_attachments', id), diveDeletedAt,
            reason: id);
      }
    });

    test('softDeleteDive leaves other dives\' attachments alone', () async {
      final other = await importFixture(712);
      await attDao.insertFile(file('other', other));
      await diveDao.softDeleteDive(diveId);
      expect(await liveIds(other), ['other']);
    });

    test('the cascaded file rows become purgeable', () async {
      await diveDao.softDeleteDive(diveId);
      final purgeable = await attDao
          .listPurgeable(DateTime.now().add(const Duration(seconds: 1)));
      expect(purgeable.map((a) => a.id).toList()..sort(), ['f1', 'f2']);
    });

    test('restoreDive restores the cascaded attachments', () async {
      await diveDao.softDeleteDive(diveId);
      await diveDao.restoreDive(diveId);
      expect(await liveIds(diveId), ['f1', 'f2', 'l1']);
    });

    test('restoreDive keeps an attachment deleted on its own beforehand',
        () async {
      // As if the user removed f2 well before deleting the dive. A direct
      // write keeps the timestamp distinct regardless of test speed.
      await ps.execute(
        'UPDATE dive_attachments SET deleted_at = 1 WHERE id = ?',
        ['f2'],
      );
      await diveDao.softDeleteDive(diveId); // cascades f1 and l1 only
      expect(await deletedAtOf('dive_attachments', 'f2'), 1);
      await diveDao.restoreDive(diveId);
      expect(await liveIds(diveId), ['f1', 'l1']);
      expect(await deletedAtOf('dive_attachments', 'f2'), 1);
    });

    test('restoreDive keeps an already-purged attachment deleted', () async {
      await diveDao.softDeleteDive(diveId);
      expect(
        await attDao.markPurged('f1',
            expectedKey: 'attachments/test-user/$diveId/f1.jpg',
            deletedBefore: DateTime(2100)),
        isNotNull,
      );
      await diveDao.restoreDive(diveId);
      expect(await liveIds(diveId), ['f2', 'l1']);
      final f1 = (await attDao.get('f1'))! as FileAttachment;
      expect(f1.deletedAt, isNotNull);
      expect(f1.uploadState, UploadState.purged);
    });

    test('merged dive: deleting each member cascades the attachments '
        'anchored to the earliest member', () async {
      // A merged dive's synthetic id has no dives row, so its media are
      // written against the earliest real member (annotationsDiveId).
      final later = await importFixture(712);
      final mergeDao = DiveMergeDao(db, ps, FakeSessionSource());
      final groupId = await mergeDao.mergeDives([diveId, later]);
      await attDao.insertFile(file('later-file', later));

      // Nothing is ever written against the synthetic group id.
      expect(await attDao.listForDive(groupId), isEmpty);

      await diveDao.softDeleteDive(diveId);
      await diveDao.softDeleteDive(later);
      expect(await attDao.listForDive(diveId), isEmpty);
      expect(await attDao.listForDive(later), isEmpty);

      await diveDao.restoreDive(diveId);
      await diveDao.restoreDive(later);
      expect(await liveIds(diveId), ['f1', 'f2', 'l1']);
      expect(await liveIds(later), ['later-file']);
    });
  });

  group('rowToDive brand fields (libdivecomputer phase 1)', () {
    Map<String, dynamic> baseRow() => {
          'id': 'd1',
          'dc_serial': 7,
          'dc_dive_number': 3,
          'start_time': 1000,
          'end_time': 2000,
          'utc_offset_minutes': null,
          'duration_seconds': 1000,
          'max_depth_mm': 30000,
          'dive_mode': 0,
          'deco_model': 0,
          'gf_low': 30,
          'gf_high': 70,
          'atmospheric_pressure_mbar': 1013,
          'water_density': 1020,
          'log_version': 1,
          'dc_model': 13,
          'dc_firmware': null,
          'sample_interval_ms': 10000,
          'gas_mixes_json': '[]',
          'tanks_json': null,
          'sensor_calibration_json': null,
          'configured_stack_seconds': null,
          'stack_remaining_at_start_seconds': null,
          'stack_remaining_at_end_seconds': null,
          'parser_version': 1,
          'imported_at': 3000,
          'subsurface_uploaded_at': null,
          'deleted_at': null,
        };

    test('rowToDive reads a pre-phase-1 row (new columns NULL)', () {
      final dive = DiveDao.rowToDive(baseRow());
      expect(dive.dcVendor, isNull);
      expect(dive.dcProduct, isNull);
      expect(dive.dcFamily, isNull);
      expect(dive.dcModelCode, isNull);
      expect(dive.matchCandidatesJson, isNull);
    });

    test('rowToDive reads brand fields and match candidates when set', () {
      final dive = DiveDao.rowToDive({
        ...baseRow(),
        'dc_vendor': 'Divesoft',
        'dc_product': 'Liberty',
        'dc_family': 0x00060000,
        'dc_model_code': 10,
        'match_candidates_json': '["a","b"]',
      });
      expect(dive.dcVendor, 'Divesoft');
      expect(dive.dcProduct, 'Liberty');
      expect(dive.dcFamily, 0x00060000);
      expect(dive.dcModelCode, 10);
      expect(dive.matchCandidatesJson, '["a","b"]');
    });
  });
}
