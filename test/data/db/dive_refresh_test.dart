import 'dart:io';
import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/ui/notifiers/dive_annotations_notifier.dart';
import 'package:ccrlogger/analysis/merge/merged_gas_mixes.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/data/import/same_dive_matcher.dart'
    show kSameDiveWindowSeconds;
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:subsurface_core/data/models/dive.dart' as model;
import 'package:subsurface_core/shearwater/parser/dive_converter.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';
import 'package:subsurface_core/subsurface_core.dart'
    show kShearwaterVendor, kSubsurfaceImportedParserVersion;

import '../../_helpers/powersync_test_helper.dart';

const _serial = 0xB89641E4;

Uint8List _raw(int n) =>
    File('test/fixtures/dives/dive_$n.bin').readAsBytesSync();

ConvertedDive _fx(int n) {
  final parsed =
      ShearwaterDiveParser(model: ShearwaterModel.petrel3).parse(_raw(n));
  return DiveConverter.convert(
    parsed: parsed,
    dcSerial: _serial,
    dcDiveNumber: n,
    dcModel: ShearwaterModel.petrel3,
  );
}

const _air = model.DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: true);
const _tx = model.DiveGasMix(oxygenPercent: 18, heliumPercent: 45, isDiluent: true);
const _o2 = model.DiveGasMix(oxygenPercent: 100, heliumPercent: 0, isDiluent: false);

/// [c] with some fields substituted; samples and events are kept.
ConvertedDive _rebuild(
  ConvertedDive c, {
  String? id,
  int? serial,
  int? number,
  int shiftSeconds = 0,
  List<model.DiveGasMix>? mixes,
  double? maxDepth,
  Duration? duration,
  String? vendor,
  bool nullVendor = false,
}) {
  final d = c.dive;
  final shift = Duration(seconds: shiftSeconds);
  return ConvertedDive(
    dive: model.Dive(
      id: id ?? d.id,
      dcSerial: serial ?? d.dcSerial,
      dcDiveNumber: number ?? d.dcDiveNumber,
      startTime: d.startTime.add(shift),
      endTime: d.endTime.add(shift),
      utcOffsetMinutes: d.utcOffsetMinutes,
      duration: duration ?? d.duration,
      maxDepthMeters: maxDepth ?? d.maxDepthMeters,
      diveMode: d.diveMode,
      decoModel: d.decoModel,
      gfLow: d.gfLow,
      gfHigh: d.gfHigh,
      atmosphericPressureMbar: d.atmosphericPressureMbar,
      waterDensityKgM3: d.waterDensityKgM3,
      logVersion: d.logVersion,
      dcModel: d.dcModel,
      gasMixes: mixes ?? d.gasMixes,
      tanks: d.tanks,
      sampleIntervalMs: d.sampleIntervalMs,
      sensorCalibration: d.sensorCalibration,
      configuredStackSeconds: d.configuredStackSeconds,
      stackRemainingAtStartSeconds: d.stackRemainingAtStartSeconds,
      stackRemainingAtEndSeconds: d.stackRemainingAtEndSeconds,
      dcVendor: nullVendor ? null : (vendor ?? d.dcVendor),
      dcProduct: d.dcProduct,
      dcFamily: d.dcFamily,
      dcModelCode: d.dcModelCode,
    ),
    samples: c.samples,
    events: c.events,
  );
}

void main() {
  late AppDatabase db;
  late DiveDao dao;
  late EquipmentDao equipment;
  late PowerSyncDatabase ps;
  late FakeSessionSource session;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final rig = await openDiveDaoForTest(db);
    dao = rig.dao;
    ps = rig.ps;
    session = rig.session;
    equipment = EquipmentDao(db, ps, rig.session);
  });
  tearDown(() => db.close());

  Future<Map<String, dynamic>> diveRow(String id) async =>
      Map<String, dynamic>.of(
          await ps.get('SELECT * FROM dives WHERE id = ?', [id]));
  Future<Map<String, dynamic>> samplesRow(String id) async =>
      Map<String, dynamic>.of(
          await ps.get('SELECT * FROM dive_samples WHERE id = ?', [id]));
  Future<int> diveCount() async =>
      (await ps.get('SELECT COUNT(*) AS n FROM dives'))['n'] as int;

  /// Stores [c] as a Subsurface copy (version -1), as the bootstrap does.
  Future<void> storeCopy(ConvertedDive c) async {
    final out = await dao.importDive(
      converted: c,
      rawBlob: Uint8List(0),
      parserVersion: kSubsurfaceImportedParserVersion,
      matchSubsurfaceCopies: false,
    );
    expect(out, ImportOutcome.inserted);
  }

  Future<void> addLayers(String id) async {
    await ps.execute(
        'INSERT INTO dive_annotations (id, owner_id, dive_id, notes, version) '
        "VALUES ('ann1', 'test-user', ?, 'nice', 1)",
        [id]);
    await ps.execute(
        'INSERT INTO dive_attachments (id, owner_id, parent_kind, parent_id, '
        "version) VALUES ('att1', 'test-user', 'dive', ?, 1)",
        [id]);
    await ps.execute(
        'INSERT INTO dive_merge_links (id, owner_id, group_id, version) '
        "VALUES (?, 'test-user', 'grp1', 1)",
        [id]);
    await ps.execute(
        'INSERT INTO dive_bailout_carry (id, owner_id, dive_id, version) '
        "VALUES ('bo1', 'test-user', ?, 1)",
        [id]);
    await equipment.setDiveCylinders(id, [
      (gasMixIndex: 0, cylinderId: 'cylA'),
      (gasMixIndex: 1, cylinderId: 'cylB'),
    ]);
  }

  Future<List<Object?>> layered() async => [
        for (final q in [
          'SELECT * FROM dive_annotations',
          'SELECT * FROM dive_attachments',
          'SELECT * FROM dive_merge_links',
          'SELECT * FROM dive_bailout_carry',
          'SELECT * FROM dive_cylinders ORDER BY id',
        ])
          (await ps.getAll(q)).map((r) => Map.of(r)).toList(),
      ];

  group('refresh in place', () {
    test(
        'a higher version refreshes under the same id and keeps annotation, '
        'attachments, merge link, bailout carry and cylinders', () async {
      final c = _fx(718);
      final id = c.dive.id;
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 1);
      await ps.execute(
          'INSERT INTO dive_annotations (id, owner_id, dive_id, notes, version) '
          "VALUES ('ann1', 'test-user', ?, 'nice', 1)",
          [id]);
      await ps.execute(
          'INSERT INTO dive_attachments (id, owner_id, parent_kind, parent_id, '
          "version) VALUES ('att1', 'test-user', 'dive', ?, 1)",
          [id]);
      await ps.execute(
          'INSERT INTO dive_merge_links (id, owner_id, group_id, version) '
          "VALUES (?, 'test-user', 'grp1', 1)",
          [id]);
      await ps.execute(
          'INSERT INTO dive_bailout_carry (id, owner_id, dive_id, version) '
          "VALUES ('bo1', 'test-user', ?, 1)",
          [id]);
      await equipment.setDiveCylinders(id, [
        (gasMixIndex: 0, cylinderId: 'cylA'),
        (gasMixIndex: 1, cylinderId: 'cylB'),
      ]);
      Future<List<Object?>> layered() async => [
            for (final q in [
              'SELECT * FROM dive_annotations',
              'SELECT * FROM dive_attachments',
              'SELECT * FROM dive_merge_links',
              'SELECT * FROM dive_bailout_carry',
              'SELECT * FROM dive_cylinders ORDER BY id',
            ])
              (await ps.getAll(q)).map((r) => Map.of(r)).toList(),
          ];
      final before = await layered();

      final out = await dao.importDive(
        converted: _rebuild(c, maxDepth: 77.0),
        rawBlob: _raw(718),
        parserVersion: 2,
      );

      expect(out, ImportOutcome.refreshed);
      expect(await diveCount(), 1);
      final row = await diveRow(id);
      expect(row['max_depth_mm'], 77000);
      expect(row['parser_version'], 2);
      expect(await layered(), before);
    });

    test('the same version only stores the raw blob', () async {
      final c = _fx(718);
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 1);
      final v = (await diveRow(c.dive.id))['version'];
      final out = await dao.importDive(
          converted: _rebuild(c, maxDepth: 77.0),
          rawBlob: _raw(711),
          parserVersion: 1);
      expect(out, ImportOutcome.unchanged);
      final row = await diveRow(c.dive.id);
      expect(row['version'], v);
      expect(row['max_depth_mm'], isNot(77000));
      expect(await dao.getRawBlob(c.dive.id), _raw(711));
    });

    test('a lower version changes nothing', () async {
      final c = _fx(718);
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 2);
      final before = await diveRow(c.dive.id);
      final out = await dao.importDive(
          converted: _rebuild(c, maxDepth: 77.0),
          rawBlob: _raw(718),
          parserVersion: 1);
      expect(out, ImportOutcome.unchanged);
      expect(await diveRow(c.dive.id), before);
    });

    test('an empty parse leaves the stored dive as it was', () async {
      final c = _fx(718);
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 1);
      final before = await diveRow(c.dive.id);
      final out = await dao.importDive(
          converted: _rebuild(c, duration: Duration.zero),
          rawBlob: _raw(718),
          parserVersion: 2);
      expect(out, ImportOutcome.rejected);
      expect(await diveRow(c.dive.id), before);
    });

    test('a refresh keeps deleted_at, imported_at and subsurface_uploaded_at',
        () async {
      final c = _fx(718);
      final id = c.dive.id;
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 1);
      await dao.markSubsurfaceUploaded([id], 1234);
      await dao.softDeleteDive(id);
      final before = await diveRow(id);
      final out = await dao.importDive(
          converted: _rebuild(c, maxDepth: 77.0),
          rawBlob: _raw(718),
          parserVersion: 2);
      expect(out, ImportOutcome.refreshed);
      final after = await diveRow(id);
      expect(after['deleted_at'], isNotNull);
      expect(after['deleted_at'], before['deleted_at']);
      expect(after['imported_at'], before['imported_at']);
      expect(after['subsurface_uploaded_at'], 1234);
    });

    test('a refresh heals a NULL owner_id but keeps a set one', () async {
      final c = _fx(718);
      final id = c.dive.id;
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 1);
      await ps.execute('UPDATE dives SET owner_id = NULL WHERE id = ?', [id]);
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 2);
      expect((await diveRow(id))['owner_id'], 'test-user');

      await ps.execute("UPDATE dives SET owner_id = 'someone' WHERE id = ?", [id]);
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 3);
      expect((await diveRow(id))['owner_id'], 'someone');
    });

    test(
        "a download refresh takes the download's dc_serial and "
        'dc_dive_number; refreshFromRawBlob keeps them', () async {
      final c = _fx(718);
      final id = c.dive.id;
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 1);
      final other = _rebuild(c, serial: 999, number: 77);

      final out = await dao.refreshFromRawBlob(
          diveId: id, converted: other, parserVersion: 2);
      expect(out, ImportOutcome.refreshed);
      var row = await diveRow(id);
      expect(row['dc_serial'], _serial);
      expect(row['dc_dive_number'], 718);

      await dao.importDive(converted: other, rawBlob: _raw(718), parserVersion: 3);
      row = await diveRow(id);
      expect(row['dc_serial'], 999);
      expect(row['dc_dive_number'], 77);
    });

    test('refreshed rows bump version on dives and dive_samples', () async {
      final c = _fx(718);
      final id = c.dive.id;
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 1);
      final d0 = (await diveRow(id))['version'] as int;
      final s0 = await samplesRow(id);
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 2);
      expect((await diveRow(id))['version'], d0 + 1);
      final s1 = await samplesRow(id);
      expect(s1['version'], (s0['version'] as int) + 1);
      expect(s1['parser_version'], 2);
      expect(s1['created_at'], s0['created_at']);
      expect(await dao.getSamples(id), isNotNull);
    });
  });

  group('Subsurface copies', () {
    // A copy of fixture 718 under another id, 30 s later, with Subsurface's
    // logbook number.
    ConvertedDive copyOf(ConvertedDive c, String id, int shift) =>
        _rebuild(c, id: id, number: 5, shiftSeconds: shift);

    test('a copy 30 s apart is refreshed under its own id', () async {
      final c = _fx(718);
      await storeCopy(copyOf(c, 'ss1', 30));
      await dao.markSubsurfaceUploaded(['ss1'], 4321);
      final before = await diveRow('ss1');

      final out = await dao.importDive(
          converted: c, rawBlob: _raw(718), parserVersion: 1);

      expect(out, ImportOutcome.refreshed);
      expect(await diveCount(), 1);
      expect(await dao.diveExists(c.dive.id), isFalse);
      final row = await diveRow('ss1');
      expect(row['parser_version'], 1);
      expect(row['dc_dive_number'], 718);
      expect(row['start_time'], before['start_time']);
      expect(row['subsurface_uploaded_at'], 4321);
      expect(row['imported_at'], before['imported_at']);
      expect(await dao.getRawBlob('ss1'), _raw(718));
      expect(await dao.getRawBlob(c.dive.id), isNull);
    });

    test('an already refreshed copy only gets the raw blob', () async {
      final c = _fx(718);
      await storeCopy(copyOf(c, 'ss1', 30));
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 1);
      final v = (await diveRow('ss1'))['version'];

      final out = await dao.importDive(
          converted: c, rawBlob: _raw(711), parserVersion: 1);

      expect(out, ImportOutcome.unchanged);
      expect(await diveCount(), 1);
      expect((await diveRow('ss1'))['version'], v);
      expect(await dao.getRawBlob('ss1'), _raw(711));
    });

    test('two matching copies: inserted as new and flagged with both ids',
        () async {
      final c = _fx(718);
      await storeCopy(copyOf(c, 'ss1', 20));
      await storeCopy(copyOf(c, 'ss2', -25));

      final out = await dao.importDive(
          converted: c, rawBlob: _raw(718), parserVersion: 1);

      expect(out, ImportOutcome.insertedFlagged);
      expect(await diveCount(), 3);
      expect((await dao.matchCandidates(c.dive.id)).toSet(), {'ss1', 'ss2'});
      expect((await diveRow('ss1'))['parser_version'], -1);
      expect((await diveRow('ss2'))['parser_version'], -1);
    });

    test('a copy outside the window is not matched', () async {
      final c = _fx(718);
      await storeCopy(copyOf(c, 'ss1', kSameDiveWindowSeconds + 1));
      final out = await dao.importDive(
          converted: c, rawBlob: _raw(718), parserVersion: 1);
      expect(out, ImportOutcome.inserted);
      expect(await diveCount(), 2);
    });

    test('matchSubsurfaceCopies: false never touches a copy', () async {
      final c = _fx(718);
      await storeCopy(copyOf(c, 'ss1', 30));
      final out = await dao.importDive(
          converted: c,
          rawBlob: _raw(718),
          parserVersion: 1,
          matchSubsurfaceCopies: false);
      expect(out, ImportOutcome.inserted);
      expect(await diveCount(), 2);
      expect((await diveRow('ss1'))['parser_version'], -1);
    });

    test('alreadyDownloadedAmong hides a refreshed copy but not an unrefreshed one',
        () async {
      final c = _fx(718);
      final start = c.dive.startTime.millisecondsSinceEpoch ~/ 1000;
      final listing = (
        diveId: c.dive.id,
        startTimeSeconds: start,
        diveNumber: 718,
      );
      await storeCopy(copyOf(c, 'ss1', 30));
      expect(
          await dao.alreadyDownloadedAmong([listing],
              vendor: kShearwaterVendor, serial: _serial),
          isEmpty);

      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 1);
      expect(
          await dao.alreadyDownloadedAmong([listing],
              vendor: kShearwaterVendor, serial: _serial),
          {c.dive.id});
    });

    test('a failed raw-blob write marks the dive and alreadyDownloadedAmong '
        'lists it again', () async {
      final c = _fx(718);
      await db.customStatement('DROP TABLE dive_raw_blobs');

      final out = await dao.importDive(
          converted: c, rawBlob: _raw(718), parserVersion: 1);

      expect(out, ImportOutcome.inserted);
      final marks = await db.select(db.diveImportMarks).get();
      expect(marks.single.diveId, c.dive.id);
      expect(marks.single.rawBlobMissing, isTrue);
      expect(
          await dao.alreadyDownloadedAmong([
            (
              diveId: c.dive.id,
              startTimeSeconds: c.dive.startTime.millisecondsSinceEpoch ~/ 1000,
              diveNumber: 718,
            )
          ], vendor: kShearwaterVendor, serial: _serial),
          isEmpty);
    });

    test('a copy refresh keeps the copy\'s start time', () async {
      final c = _fx(718);
      await storeCopy(copyOf(c, 'ss1', 30));
      final before = await diveRow('ss1');
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 1);
      final row = await diveRow('ss1');
      expect(row['start_time'], before['start_time']);
      expect((row['end_time'] as int) - (row['start_time'] as int),
          (c.dive.endTime.millisecondsSinceEpoch -
                  c.dive.startTime.millisecondsSinceEpoch) ~/
              1000);
    });

    test('a re-download after that still finds the refreshed copy', () async {
      final c = _fx(718);
      await storeCopy(copyOf(c, 'ss1', 30));
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 1);
      expect(
          await dao.importDive(
              converted: c, rawBlob: _raw(718), parserVersion: 1),
          ImportOutcome.unchanged);
      expect(await diveCount(), 1);
      expect(
          await dao.alreadyDownloadedAmong([
            (
              diveId: c.dive.id,
              startTimeSeconds: c.dive.startTime.millisecondsSinceEpoch ~/ 1000,
              diveNumber: 718,
            )
          ], vendor: kShearwaterVendor, serial: _serial),
          {c.dive.id});
    });

    test('an incoming copy never replaces a stored raw blob', () async {
      final c = _fx(718);
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 1);
      await dao.importDive(
          converted: c,
          rawBlob: Uint8List(0),
          parserVersion: kSubsurfaceImportedParserVersion,
          matchSubsurfaceCopies: false);
      expect(await dao.getRawBlob(c.dive.id), _raw(718));
      await dao.importDive(
          converted: c,
          rawBlob: _raw(711),
          parserVersion: kSubsurfaceImportedParserVersion,
          matchSubsurfaceCopies: false);
      expect(await dao.getRawBlob(c.dive.id), _raw(718));
    });

    test('a refreshed copy and an unrefreshed copy in the window: the '
        'refreshed one is used, nothing inserted', () async {
      final c = _fx(718);
      await storeCopy(copyOf(c, 'ss2', 30));
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 1);
      await storeCopy(copyOf(c, 'ss1', 10));

      final out = await dao.importDive(
          converted: c, rawBlob: _raw(711), parserVersion: 1);

      expect(out, ImportOutcome.unchanged);
      expect(await diveCount(), 2);
      expect(await dao.getRawBlob('ss2'), _raw(711));
      expect((await diveRow('ss1'))['parser_version'], -1);
    });

    test('layered rows survive a copy refresh', () async {
      final c = _fx(718);
      await storeCopy(copyOf(c, 'ss1', 30));
      await addLayers('ss1');
      final before = await layered();
      final out = await dao.importDive(
          converted: c, rawBlob: _raw(718), parserVersion: 1);
      expect(out, ImportOutcome.refreshed);
      expect(await layered(), before);
    });

    test('dc_vendor COALESCE: a NULL incoming vendor keeps the stored one',
        () async {
      final c = _rebuild(_fx(718), nullVendor: true);
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 1);
      await ps.execute("UPDATE dives SET dc_vendor = 'Keeper' WHERE id = ?",
          [c.dive.id]);
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 2);
      expect((await diveRow(c.dive.id))['dc_vendor'], 'Keeper');
    });

    test('the rawBlobMissing mark is cleared by a later successful write',
        () async {
      final c = _fx(718);
      await db.customStatement('DROP TABLE dive_raw_blobs');
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 1);
      expect((await db.select(db.diveImportMarks).get()).single.rawBlobMissing,
          isTrue);
      await db.createMigrator().createTable(db.diveRawBlobs);
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 1);
      expect((await db.select(db.diveImportMarks).get()).single.rawBlobMissing,
          isFalse);
      expect(await dao.getRawBlob(c.dive.id), _raw(718));
    });

    test('a throw mid-refresh leaves PowerSync unchanged', () async {
      final c = _rebuild(_fx(718), mixes: [_air, _tx]);
      final id = c.dive.id;
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 1);
      await equipment.setDiveCylinders(id, [
        (gasMixIndex: 0, cylinderId: 'cAir'),
        (gasMixIndex: 1, cylinderId: 'cTx'),
      ]);
      // The gone mix moves to index -1: an INSERT, which the trigger refuses
      // after the dives and dive_samples updates have run.
      await ps.execute('CREATE TRIGGER boom INSTEAD OF INSERT ON dive_cylinders '
          "BEGIN SELECT RAISE(ABORT, 'boom'); END");
      final dBefore = await diveRow(id);
      final sBefore = await samplesRow(id);
      final cBefore = await layered();

      await expectLater(
          dao.importDive(
              converted: _rebuild(c, mixes: [_air], maxDepth: 77.0),
              rawBlob: _raw(718),
              parserVersion: 2),
          throwsA(anything));

      expect(await diveRow(id), dBefore);
      expect(await samplesRow(id), sBefore);
      expect(await layered(), cBefore);
    });
  });

  group('cylinders across a refresh', () {
    Future<ConvertedDive> storeWithMixes(List<model.DiveGasMix> mixes) async {
      final c = _rebuild(_fx(718), mixes: mixes);
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 1);
      return c;
    }

    test('cylinders follow their mix when the refreshed gas list is reordered',
        () async {
      final c = await storeWithMixes([_air, _tx, _o2]);
      final id = c.dive.id;
      await equipment.setDiveCylinders(id, [
        (gasMixIndex: 0, cylinderId: 'cAir'),
        (gasMixIndex: 1, cylinderId: 'cTx'),
        (gasMixIndex: 2, cylinderId: 'cO2'),
      ]);

      await dao.importDive(
          converted: _rebuild(c, mixes: [_o2, _air, _tx]),
          rawBlob: _raw(718),
          parserVersion: 2);

      final rows = await equipment.listCylindersForDive(id);
      expect({for (final r in rows) r.gasMixIndex: r.cylinderId},
          {0: 'cO2', 1: 'cAir', 2: 'cTx'});
    });

    test('a cylinder whose mix is gone survives as unassigned', () async {
      final c = await storeWithMixes([_air, _tx]);
      final id = c.dive.id;
      await equipment.setDiveCylinders(id, [
        (gasMixIndex: 0, cylinderId: 'cAir'),
        (gasMixIndex: 1, cylinderId: 'cTx'),
      ]);

      await dao.importDive(
          converted: _rebuild(c, mixes: [_air]),
          rawBlob: _raw(718),
          parserVersion: 2);

      final rows = await equipment.listCylindersForDive(id);
      expect({for (final r in rows) r.gasMixIndex: r.cylinderId},
          {-1: 'cTx', 0: 'cAir'});
    });
  });

  group('cylinder rows after a refresh', () {
    Future<Map<int, String?>> cylinders(String id) async => {
          for (final r in await equipment.listCylindersForDive(id))
            r.gasMixIndex: r.cylinderId,
        };

    test('an empty row whose mix is gone is dropped, not kept as unassigned',
        () async {
      final c = _rebuild(_fx(718), mixes: [_air, _tx]);
      final id = c.dive.id;
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 1);
      await equipment.setDiveCylinders(id, [
        (gasMixIndex: 0, cylinderId: 'cAir'),
        (gasMixIndex: 1, cylinderId: null),
      ]);
      await dao.importDive(
          converted: _rebuild(c, mixes: [_air]),
          rawBlob: _raw(718),
          parserVersion: 2);
      expect(await cylinders(id), {0: 'cAir'});
    });

    test('a stale cylinder save does not undo a refresh', () async {
      final c = _rebuild(_fx(718), mixes: [_air, _tx, _o2]);
      final id = c.dive.id;
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 1);
      await equipment.setDiveCylinders(id, [
        (gasMixIndex: 0, cylinderId: 'cAir'),
        (gasMixIndex: 1, cylinderId: 'cTx'),
        (gasMixIndex: 2, cylinderId: 'cO2'),
      ]);
      final notifier = DiveAnnotationsNotifier(
          DiveAnnotationsDao(ps, session), equipment);
      await notifier.load(id); // the screen opens

      await dao.importDive(
          converted: _rebuild(c, mixes: [_o2, _air]),
          rawBlob: _raw(718),
          parserVersion: 2);
      notifier.setNotes('edited on the old screen');
      await notifier.save();

      // cTx lost its mix: unassigned; the others followed theirs.
      expect(await cylinders(id), {-1: 'cTx', 0: 'cO2', 1: 'cAir'});
      final soft = await ps.getAll(
          'SELECT id FROM dive_cylinders WHERE dive_id = ? AND deleted_at IS NOT NULL',
          [id]);
      expect(soft, isNotEmpty);
    });

    test('a save still writes the cylinder the user changed', () async {
      final c = _rebuild(_fx(718), mixes: [_air, _tx]);
      final id = c.dive.id;
      await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 1);
      await equipment.setDiveCylinders(id, [
        (gasMixIndex: 0, cylinderId: 'cAir'),
        (gasMixIndex: 1, cylinderId: 'cTx'),
      ]);
      final notifier = DiveAnnotationsNotifier(
          DiveAnnotationsDao(ps, session), equipment);
      await notifier.load(id);
      notifier.setCylinderForMix(1, 'cOther');
      await notifier.save();
      expect(await cylinders(id), {0: 'cAir', 1: 'cOther'});
    });

    // Two members; the merged gas list is the de-duplicated union in start
    // order, and the rows live under the earliest member.
    Future<({String first, String second, ConvertedDive a, ConvertedDive b})>
        mergedPair(List<model.DiveGasMix> aMixes,
            List<model.DiveGasMix> bMixes) async {
      final a = _rebuild(_fx(711), mixes: aMixes);
      final b = _rebuild(_fx(712), mixes: bMixes);
      expect(a.dive.startTime.isBefore(b.dive.startTime), isTrue);
      await dao.importDive(converted: a, rawBlob: _raw(718), parserVersion: 1);
      await dao.importDive(converted: b, rawBlob: _raw(718), parserVersion: 1);
      for (final id in [a.dive.id, b.dive.id]) {
        await ps.execute(
            'INSERT INTO dive_merge_links (id, owner_id, group_id, version) '
            "VALUES (?, 'test-user', 'grp', 1)",
            [id]);
      }
      return (first: a.dive.id, second: b.dive.id, a: a, b: b);
    }

    test("a refresh of the earliest member remaps the merged dive's cylinders",
        () async {
      final m = await mergedPair([_air, _tx], [_tx, _o2]);
      await equipment.setDiveCylinders(m.first, [
        (gasMixIndex: 0, cylinderId: 'cAir'),
        (gasMixIndex: 1, cylinderId: 'cTx'),
        (gasMixIndex: 2, cylinderId: 'cO2'),
      ]);
      await dao.importDive(
          converted: _rebuild(m.a, mixes: [_tx, _air]),
          rawBlob: _raw(718),
          parserVersion: 2);
      final merged = mergeGasMixLists([
        [_tx, _air],
        [_tx, _o2]
      ]).mixes;
      expect(merged, hasLength(3));
      final rows = await cylinders(m.first);
      expect({for (final e in rows.entries) merged[e.key].oxygenPercent: e.value},
          {18: 'cTx', 21: 'cAir', 100: 'cO2'});
    });

    test("a refresh of a later member remaps the merged dive's cylinders",
        () async {
      final m = await mergedPair([_air], [_tx, _o2]);
      await equipment.setDiveCylinders(m.first, [
        (gasMixIndex: 0, cylinderId: 'cAir'),
        (gasMixIndex: 1, cylinderId: 'cTx'),
        (gasMixIndex: 2, cylinderId: 'cO2'),
      ]);
      await dao.importDive(
          converted: _rebuild(m.b, mixes: [_o2, _tx]),
          rawBlob: _raw(718),
          parserVersion: 2);
      final merged = mergeGasMixLists([
        [_air],
        [_o2, _tx]
      ]).mixes;
      final rows = await cylinders(m.first);
      expect({for (final e in rows.entries) merged[e.key].oxygenPercent: e.value},
          {21: 'cAir', 100: 'cO2', 18: 'cTx'});
      expect(rows, {0: 'cAir', 1: 'cO2', 2: 'cTx'});
    });
  });
}
