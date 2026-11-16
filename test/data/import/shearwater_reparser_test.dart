import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/data/import/import_problem_reporter.dart';
import 'package:ccrlogger/data/import/shearwater_reparser.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/parser_version.dart';
import 'package:subsurface_core/shearwater/parser/constants.dart' show infoEventTagLog;
import 'package:ccrlogger/sync/cloud/sync_status_source.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:subsurface_core/data/models/dive.dart' as model;
import 'package:subsurface_core/shearwater/parser/dive_converter.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';
import 'package:subsurface_core/subsurface_core.dart'
    show kSubsurfaceImportedParserVersion;

import '../../_helpers/patched_dive_718.dart';
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

class _Report {
  final List<(Object, String)> calls = [];
  void call(Object error, StackTrace? stack, String where) =>
      calls.add((error, where));
}

void main() {
  late AppDatabase db;
  late DiveDao dao;
  late EquipmentDao equipment;
  late PowerSyncDatabase ps;
  late _Report report;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final rig = await openDiveDaoForTest(db);
    dao = rig.dao;
    ps = rig.ps;
    equipment = EquipmentDao(db, ps, rig.session);
    report = _Report();
  });
  tearDown(() => db.close());

  ShearwaterReparser reparser({
    Future<bool> Function()? waitUntilSynced,
    ParseRunner? parse,
  }) =>
      ShearwaterReparser(
        diveDao: dao,
        drift: db,
        report: report.call,
        waitUntilSynced: waitUntilSynced ?? () async => true,
        parse: parse,
      );

  /// Stores dive [n] as an older parse with its raw blob, damaged so a
  /// refresh is visible.
  Future<String> storeOld(int n, {int version = 1}) async {
    final c = _fx(n);
    await dao.importDive(
        converted: c, rawBlob: _raw(n), parserVersion: version);
    await ps.execute('UPDATE dives SET max_depth_mm = 1 WHERE id = ?',
        [c.dive.id]);
    return c.dive.id;
  }

  Future<Map<String, dynamic>> row(String id) async =>
      Map.of(await ps.get('SELECT * FROM dives WHERE id = ?', [id]));

  Future<int?> failedMark(String id) async =>
      (await (db.select(db.diveImportMarks)..where((t) => t.diveId.equals(id)))
              .getSingleOrNull())
          ?.reparseFailedVersion;

  test('refreshes every older Shearwater dive with a local raw blob to the '
      'current version', () async {
    final a = await storeOld(718);
    final b = await storeOld(717);

    final r = await reparser().run();

    expect((r.refreshed, r.failed, r.skipped), (2, 0, 0));
    for (final id in [a, b]) {
      final d = await row(id);
      expect(d['parser_version'], kShearwaterParserVersion);
      expect(d['max_depth_mm'], greaterThan(1));
    }
    expect(report.calls, isEmpty);
  });

  test('refreshes a Subsurface copy that has a non-empty local raw blob',
      () async {
    final c = _fx(716);
    await dao.importDive(
      converted: c,
      rawBlob: Uint8List(0),
      parserVersion: kSubsurfaceImportedParserVersion,
      matchSubsurfaceCopies: false,
    );
    await db.into(db.diveRawBlobs).insert(
        DiveRawBlobsCompanion.insert(diveId: c.dive.id, rawBlob: _raw(716)));

    final r = await reparser().run();

    expect(r.refreshed, 1);
    expect((await row(c.dive.id))['parser_version'], kShearwaterParserVersion);
  });

  test('skips dives without a raw blob, deleted dives and libdivecomputer '
      'dives', () async {
    final noBlob = _fx(715);
    await dao.importDive(
      converted: noBlob,
      rawBlob: Uint8List(0),
      parserVersion: 1,
    );
    final deleted = await storeOld(714);
    await ps.execute(
        'UPDATE dives SET deleted_at = 5 WHERE id = ?', [deleted]);
    final libdc = await storeOld(713);
    await ps.execute(
        'UPDATE dives SET dc_family = 1 WHERE id = ?', [libdc]);

    final r = await reparser().run();

    expect((r.refreshed, r.failed, r.skipped), (0, 0, 1));
    expect((await row(noBlob.dive.id))['parser_version'], 1);
    expect((await row(deleted))['parser_version'], 1);
    expect((await row(libdc))['parser_version'], 1);
    expect(report.calls, isEmpty);
  });

  test('a dive with an empty raw-blob row is skipped, not reported',
      () async {
    final c = _fx(712);
    await dao.importDive(
      converted: c,
      rawBlob: Uint8List(0),
      parserVersion: kSubsurfaceImportedParserVersion,
      matchSubsurfaceCopies: false,
    );
    await db.into(db.diveRawBlobs).insert(
        DiveRawBlobsCompanion.insert(diveId: c.dive.id, rawBlob: Uint8List(0)));

    final r = await reparser().run();

    expect((r.refreshed, r.failed), (0, 0));
    expect(report.calls, isEmpty);
    expect(await failedMark(c.dive.id), isNull);
    expect((await row(c.dive.id))['parser_version'],
        kSubsurfaceImportedParserVersion);
  });

  test('a blob that fails to parse is reported once and skipped on the next '
      'run', () async {
    final id = await storeOld(718);
    await db.into(db.diveRawBlobs).insertOnConflictUpdate(
        DiveRawBlobsCompanion(
            diveId: Value(id), rawBlob: Value(Uint8List.fromList([1, 2, 3]))));

    final first = await reparser().run();
    expect((first.refreshed, first.failed), (0, 1));
    expect(report.calls.length, 1);
    expect(report.calls.single.$2, 'reparse');
    expect(await failedMark(id), kShearwaterParserVersion);
    expect((await row(id))['parser_version'], 1);

    final second = await reparser().run();
    expect((second.refreshed, second.failed), (0, 0));
    expect(second.skipped, 1);
    expect(report.calls.length, 1);
  });

  test('a rejected parse is marked and reported as UnusableParse', () async {
    final id = await storeOld(718);
    final r = await reparser(
      parse: (bytes, modelIndex, serial, number) async {
        final c = _fx(718);
        final d = c.dive;
        return ConvertedDive(
          dive: model.Dive(
            id: d.id,
            dcSerial: d.dcSerial,
            dcDiveNumber: d.dcDiveNumber,
            startTime: d.startTime,
            endTime: d.endTime,
            utcOffsetMinutes: d.utcOffsetMinutes,
            duration: Duration.zero,
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
          ),
          samples: c.samples,
        );
      },
    ).run();
    expect(r.failed, 1);
    expect(report.calls.single.$1, isA<UnusableParse>());
    expect(report.calls.single.$2, 'reparse');
    expect(await failedMark(id), kShearwaterParserVersion);
    expect((await row(id))['parser_version'], 1);
  });

  test('an out-of-range model index is marked and reported, never thrown',
      () async {
    final id = await storeOld(718);
    await ps.execute('UPDATE dives SET dc_model = 999 WHERE id = ?', [id]);

    final r = await reparser().run();

    expect(r.failed, 1);
    expect(report.calls.single.$2, 'reparse');
    expect(await failedMark(id), kShearwaterParserVersion);
  });

  test('an interrupted run carries on: a second run refreshes only what is '
      'left', () async {
    final ids = [
      await storeOld(718),
      await storeOld(717),
      await storeOld(716),
    ];

    // The first run is "killed" after one dive: its parser never returns
    // for the second one, and the run is abandoned.
    var parsed = 0;
    final hang = Completer<ConvertedDive>();
    unawaited(reparser(
      parse: (bytes, modelIndex, serial, number) {
        if (++parsed == 2) return hang.future;
        return defaultParseRunner(bytes, modelIndex, serial, number);
      },
    ).run());
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (true) {
      if (DateTime.now().isAfter(deadline)) fail('first dive never refreshed');
      final n = (await ps.get('SELECT COUNT(*) AS n FROM dives '
              'WHERE parser_version = ?', [kShearwaterParserVersion]))['n']
          as int;
      if (n == 1) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    final second = await reparser().run();

    expect((second.refreshed, second.failed), (2, 0));
    for (final id in ids) {
      expect((await row(id))['parser_version'], kShearwaterParserVersion);
    }
    expect(report.calls, isEmpty);
  });

  test('a write error is reported once, stops the run, is not marked and '
      'is retried next run', () async {
    final a = await storeOld(718);
    final b = await storeOld(717);
    await ps.execute('CREATE TRIGGER boom INSTEAD OF UPDATE ON dives '
        "BEGIN SELECT RAISE(ABORT, 'boom'); END");

    final first = await reparser().run();

    expect((first.refreshed, first.failed), (0, 0));
    expect(report.calls.length, 1);
    expect(report.calls.single.$2, 'reparse');
    expect(await failedMark(a), isNull);
    expect(await failedMark(b), isNull);

    await ps.execute('DROP TRIGGER boom');
    final second = await reparser().run();
    expect(second.refreshed, 2);
    expect(report.calls.length, 1);
    for (final id in [a, b]) {
      expect((await row(id))['parser_version'], kShearwaterParserVersion);
    }
  });

  test('a v1 row gains its events, vendor, product and samples version',
      () async {
    final c = _fx(718);
    final id = c.dive.id;
    await dao.importDive(
        converted: c, rawBlob: patchedDive718(), parserVersion: 1);
    // What a build from before the reader update stored.
    await ps.execute(
        'UPDATE dives SET dc_vendor = NULL, dc_product = NULL WHERE id = ?',
        [id]);
    await ps.execute(
        'UPDATE dive_samples SET events_blob = NULL, parser_version = NULL '
        'WHERE id = ?',
        [id]);
    expect(await dao.getEvents(id), isEmpty);

    final r = await reparser().run();

    expect(r.refreshed, 1);
    final events = await dao.getEvents(id);
    expect(events, hasLength(2));
    final interval = c.dive.sampleIntervalMs;
    expect(events[0].type, DiveEventType.bookmark);
    expect(events[0].rawType, infoEventTagLog);
    expect(events[0].timeMs, 9 * interval);
    expect(events[0].value, 7);
    expect(events[0].bearing, 270);
    expect(events[1].type, DiveEventType.bookmark);
    expect(events[1].rawType, infoEventTagLog);
    expect(events[1].timeMs, 18 * interval);
    expect(events[1].value, 8);
    expect(events[1].bearing, isNull);
    final d = await row(id);
    expect(d['dc_vendor'], 'Shearwater');
    expect(d['dc_product'], 'Petrel 3');
    expect(d['parser_version'], kShearwaterParserVersion);
    expect((await ps.get('SELECT parser_version FROM dive_samples '
            'WHERE id = ?', [id]))['parser_version'],
        kShearwaterParserVersion);
  });

  test('an unchanged gas list leaves every cylinder row untouched', () async {
    final id = await storeOld(718);
    await equipment.setDiveCylinders(id, [
      (gasMixIndex: 0, cylinderId: 'cylA'),
      (gasMixIndex: 7, cylinderId: 'cylOut'),
    ]);
    final before = [
      for (final r in await ps.getAll(
          'SELECT * FROM dive_cylinders ORDER BY id'))
        Map.of(r)
    ];
    expect(before, hasLength(2));

    await reparser().run();

    expect((await row(id))['parser_version'], kShearwaterParserVersion);
    expect([
      for (final r in await ps.getAll(
          'SELECT * FROM dive_cylinders ORDER BY id'))
        Map.of(r)
    ], before);
  });

  test('a candidate with a NULL serial is marked and reported, not thrown',
      () async {
    final id = await storeOld(718);
    await ps.execute('UPDATE dives SET dc_serial = NULL WHERE id = ?', [id]);

    final r = await reparser().run();

    expect(r.failed, 1);
    expect(report.calls.single.$2, 'reparse');
    expect(await failedMark(id), kShearwaterParserVersion);
  });

  test('nothing runs when waitUntilSynced returns false', () async {
    final id = await storeOld(718);

    final r = await reparser(waitUntilSynced: () async => false).run();

    expect((r.refreshed, r.failed, r.skipped), (0, 0, 0));
    expect((await row(id))['parser_version'], 1);
  });

  test('keeps annotations, cylinders and the id', () async {
    final id = await storeOld(718);
    await ps.execute(
        'INSERT INTO dive_annotations (id, owner_id, dive_id, notes, version) '
        "VALUES ('ann1', 'test-user', ?, 'nice', 1)",
        [id]);
    await equipment.setDiveCylinders(id, [
      (gasMixIndex: 0, cylinderId: 'cylA'),
    ]);
    Future<List<Object?>> layered() async => [
          for (final q in [
            'SELECT * FROM dive_annotations',
            'SELECT * FROM dive_cylinders ORDER BY id',
          ])
            (await ps.getAll(q)).map((r) => Map.of(r)).toList(),
        ];
    final before = await layered();

    await reparser().run();

    expect((await row(id))['parser_version'], kShearwaterParserVersion);
    expect(await layered(), before);
    expect((await ps.getAll('SELECT id FROM dives')).length, 1);
  });

  group('waitUntilSynced', () {
    late StreamController<SyncStatusSnapshot> controller;
    late DateTime clock;
    var current = const SyncStatusSnapshot();

    setUp(() {
      controller = StreamController<SyncStatusSnapshot>.broadcast();
      clock = DateTime.utc(2026, 11, 16, 12);
      current = const SyncStatusSnapshot();
    });
    tearDown(() => controller.close());

    Future<bool> Function() wait({bool signedIn = true}) =>
        waitUntilSyncedFor(
          isSignedIn: () => signedIn,
          status: _FakeStatus(() => current, controller.stream),
          now: () => clock,
          timeout: const Duration(milliseconds: 200),
        );

    test('signed out completes true at once', () async {
      expect(await wait(signedIn: false)(), isTrue);
    });

    test('completes true when connected, idle and synced after the start',
        () async {
      final w = wait()();
      controller.add(SyncStatusSnapshot(
          connected: true, downloading: true, lastSyncedAt: clock));
      // Persisted from before the launch: does not count.
      controller.add(SyncStatusSnapshot(
          connected: true,
          lastSyncedAt: clock.subtract(const Duration(hours: 1))));
      controller.add(SyncStatusSnapshot(
          connected: true,
          lastSyncedAt: clock.add(const Duration(seconds: 3))));
      expect(await w, isTrue);
    });

    test('a lastSyncedAt truncated to the second, in the start second, counts',
        () async {
      clock = DateTime.utc(2026, 11, 16, 12, 0, 0, 700, 300);
      final w = wait()();
      controller.add(SyncStatusSnapshot(
          connected: true, lastSyncedAt: DateTime.utc(2026, 11, 16, 12)));
      expect(await w, isTrue);
    });

    test('the value present at the start never counts', () async {
      clock = DateTime.utc(2026, 11, 16, 12, 0, 0, 700);
      final previous = DateTime.utc(2026, 11, 16, 12);
      current = SyncStatusSnapshot(connected: true, lastSyncedAt: previous);
      final w = wait()();
      controller.add(SyncStatusSnapshot(connected: true, lastSyncedAt: previous));
      expect(await w, isFalse);
    });

    test('a sync already shown after the baseline completes true at once',
        () async {
      clock = DateTime.utc(2026, 11, 16, 12, 0, 5);
      final baseline = SyncBaseline(
          startedAt: DateTime.utc(2026, 11, 16, 12),
          lastSyncedAt: DateTime.utc(2026, 11, 15));
      current = SyncStatusSnapshot(
          connected: true, lastSyncedAt: DateTime.utc(2026, 11, 16, 12, 0, 2));
      final w = waitUntilSyncedFor(
        isSignedIn: () => true,
        status: _FakeStatus(() => current, controller.stream),
        now: () => clock,
        baseline: baseline,
        timeout: const Duration(seconds: 30),
      );
      // No stream event: the immediate check must be enough.
      expect(await w(), isTrue);
    });

    test('not connected never counts, even with a fresh lastSyncedAt',
        () async {
      final w = wait()();
      controller.add(SyncStatusSnapshot(
          connected: false, lastSyncedAt: clock.add(const Duration(seconds: 3))));
      expect(await w, isFalse);
    });

    test('completes false after the timeout', () async {
      final w = wait()();
      controller.add(SyncStatusSnapshot(
          connected: true,
          lastSyncedAt: clock.subtract(const Duration(hours: 1))));
      expect(await w, isFalse);
    });
  });
}

class _FakeStatus implements SyncStatusSource {
  _FakeStatus(this._current, this._stream);
  final SyncStatusSnapshot Function() _current;
  final Stream<SyncStatusSnapshot> _stream;
  @override
  SyncStatusSnapshot get currentStatus => _current();
  @override
  Stream<SyncStatusSnapshot> get statusStream => _stream;
}
