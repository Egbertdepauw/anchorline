import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/import/fit_reparser.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fit_reader/fit_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

import '../../_helpers/fit_test_support.dart';
import '../../_helpers/powersync_test_helper.dart';

class _Report {
  final List<(Object, String)> calls = [];
  void call(Object error, StackTrace? stack, String where) =>
      calls.add((error, where));
}

void main() {
  late AppDatabase db;
  late DiveDao dao;
  late PowerSyncDatabase ps;
  late _Report report;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final rig = await openDiveDaoForTest(db);
    dao = rig.dao;
    ps = rig.ps;
    report = _Report();
  });
  tearDown(() => db.close());

  FitReparser reparser() => FitReparser(
        diveDao: dao,
        drift: db,
        report: report.call,
        waitUntilSynced: () async => true,
      );

  Future<Map<String, dynamic>> row(String id) async =>
      Map.of(await ps.get('SELECT * FROM dives WHERE id = ?', [id]));

  Future<int?> failedMark(String id) async =>
      (await (db.select(db.diveImportMarks)..where((t) => t.diveId.equals(id)))
              .getSingleOrNull())
          ?.reparseFailedVersion;

  /// Stores the fixture as an older parse with its ALFT blob, damaged so a
  /// refresh is visible.
  Future<String> storeOld({String name = kFitFixture, int version = 0}) async {
    final c = fitDive(name);
    await dao.importDive(
        converted: c,
        rawBlob: fitBlob(fitFixtureBytes(name)),
        parserVersion: version);
    await ps.execute('UPDATE dives SET max_depth_mm = 1 WHERE id = ?',
        [c.dive.id]);
    return c.dive.id;
  }

  test('re-parses FIT dives below the current version and keeps id, '
      'annotations and fingerprint', () async {
    final id = await storeOld();
    final fp = (await row(id))['dc_fingerprint'];
    await ps.execute(
        'INSERT INTO dive_annotations (id, owner_id, dive_id, notes, version) '
        "VALUES ('ann1', 'test-user', ?, 'nice', 1)",
        [id]);
    final startBefore = (await row(id))['start_time'];

    final r = await reparser().run();

    expect((r.refreshed, r.failed, r.skipped), (1, 0, 0));
    final d = await row(id);
    expect(d['parser_version'], kFitParserVersion);
    expect(d['max_depth_mm'], greaterThan(1));
    expect(d['dc_fingerprint'], fp);
    expect(d['dc_family'], -1);
    expect(d['start_time'], startBefore);
    expect(
        (await ps.get('SELECT notes FROM dive_annotations WHERE id = ?',
            ['ann1']))['notes'],
        'nice');
    expect(report.calls, isEmpty);
  });

  test('picks the session by the stored fingerprint', () async {
    final id = await storeOld();
    final other = fitDive('garmin_mk1_ccr_2023-10-21.fit');
    final mine = fitDive();
    final r = await FitReparser(
      diveDao: dao,
      drift: db,
      report: report.call,
      waitUntilSynced: () async => true,
      // A file whose first dive is another one: only the fingerprint tells.
      parse: (fit) async => [other, mine],
    ).run();

    expect(r.refreshed, 1);
    expect((await row(id))['max_depth_mm'],
        (mine.dive.maxDepthMeters * 1000).round());
  });

  test('skips Shearwater and libdivecomputer rows, deleted dives, and rows '
      'without a local blob', () async {
    final noBlob = fitDive('garmin_mk1_ccr_2023-10-21.fit');
    await dao.importDive(
        converted: noBlob, rawBlob: Uint8List(0), parserVersion: 0);
    final deleted = await storeOld();
    await ps.execute('UPDATE dives SET deleted_at = 5 WHERE id = ?', [deleted]);
    final shear = await storeOld(name: 'suunto_ocean_nitrox.fit');
    await ps.execute('UPDATE dives SET dc_family = NULL WHERE id = ?', [shear]);
    final libdc = rebuildFit(fitDive(),
        id: 'libdc-row', family: 5, fingerprint: 'aa11aa11');
    await dao.importDive(
        converted: libdc, rawBlob: fitBlob(), parserVersion: 0);

    final r = await reparser().run();

    expect((r.refreshed, r.failed, r.skipped), (0, 0, 1));
    expect((await row(noBlob.dive.id))['parser_version'], 0);
    expect((await row(deleted))['parser_version'], 0);
    expect((await row(shear))['parser_version'], 0);
    expect((await row('libdc-row'))['parser_version'], 0);
    expect(report.calls, isEmpty);
  });

  test('a blob that does not decode as ALFT is marked as failed for this '
      'version only', () async {
    final id = await storeOld();
    await db.into(db.diveRawBlobs).insertOnConflictUpdate(
        DiveRawBlobsCompanion(
            diveId: Value(id), rawBlob: Value(Uint8List.fromList([1, 2, 3]))));

    final first = await reparser().run();
    expect((first.refreshed, first.failed), (0, 1));
    expect(report.calls.length, 1);
    expect(report.calls.single.$2, 'reparse');
    expect(await failedMark(id), kFitParserVersion);
    expect((await row(id))['parser_version'], 0);

    final second = await reparser().run();
    expect((second.refreshed, second.failed, second.skipped), (0, 0, 1));
    expect(report.calls.length, 1);

    // A mark from an older reader version does not hold this one back.
    await db.into(db.diveImportMarks).insertOnConflictUpdate(
        DiveImportMarksCompanion(
            diveId: Value(id),
            reparseFailedVersion: const Value(kFitParserVersion - 1)));
    await db.into(db.diveRawBlobs).insertOnConflictUpdate(
        DiveRawBlobsCompanion(diveId: Value(id), rawBlob: Value(fitBlob())));
    final third = await reparser().run();
    expect(third.refreshed, 1);
  });

  test('a file whose sessions do not include the stored fingerprint is '
      'marked as failed', () async {
    final id = await storeOld();
    await ps.execute(
        "UPDATE dives SET dc_fingerprint = 'ffff' WHERE id = ?", [id]);

    final r = await reparser().run();

    expect((r.refreshed, r.failed), (0, 1));
    expect(await failedMark(id), kFitParserVersion);
  });

  test('gives up without touching anything when the sync never settles',
      () async {
    final id = await storeOld();
    final r = await FitReparser(
      diveDao: dao,
      drift: db,
      report: report.call,
      waitUntilSynced: () async => false,
    ).run();
    expect((r.refreshed, r.failed, r.skipped), (0, 0, 0));
    expect((await row(id))['parser_version'], 0);
  });
}
