import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:drift/native.dart';
import 'package:fit_reader/fit_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:subsurface_core/subsurface_core.dart'
    show kFitDcFamily, kSubsurfaceImportedParserVersion;

import '../../_helpers/fit_test_support.dart';
import '../../_helpers/powersync_test_helper.dart';

void main() {
  late AppDatabase db;
  late DiveDao dao;
  late PowerSyncDatabase ps;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final rig = await openDiveDaoForTest(db);
    dao = rig.dao;
    ps = rig.ps;
  });
  tearDown(() => db.close());

  Future<Map<String, dynamic>> row(String id) async =>
      Map.of(await ps.get('SELECT * FROM dives WHERE id = ?', [id]));
  Future<int> diveCount() async =>
      (await ps.get('SELECT COUNT(*) AS n FROM dives'))['n'] as int;

  test('a FIT dive imports with family -1, its fingerprint, and an ALFT raw '
      'blob', () async {
    final c = fitDive();
    final blob = fitBlob();

    final out = await dao.importDive(
        converted: c, rawBlob: blob, parserVersion: kFitParserVersion);

    expect(out, ImportOutcome.inserted);
    final r = await row(c.dive.id);
    expect(r['dc_family'], kFitDcFamily);
    expect(r['dc_fingerprint'], c.dive.dcFingerprint);
    expect(r['dc_fingerprint'], isNotEmpty);
    expect(r['dc_vendor'], 'Garmin');
    expect(r['parser_version'], kFitParserVersion);
    final stored = (await dao.getRawBlob(c.dive.id))!;
    expect(stored.sublist(0, 4), 'ALFT'.codeUnits);
    expect(stored, blob);
    final env = FitEnvelope.decode(stored);
    expect(mapFitFile(env.fit).single.dive.id, c.dive.id);
  });

  test('the same dive again is unchanged; a newer FIT version refreshes it',
      () async {
    final c = fitDive();
    await dao.importDive(
        converted: c, rawBlob: fitBlob(), parserVersion: kFitParserVersion);
    final before = await row(c.dive.id);

    final again = await dao.importDive(
        converted: rebuildFit(c, maxDepth: 77.0),
        rawBlob: fitBlob(),
        parserVersion: kFitParserVersion);
    expect(again, ImportOutcome.unchanged);
    expect(await row(c.dive.id), before);

    final newer = await dao.importDive(
        converted: rebuildFit(c, maxDepth: 77.0),
        rawBlob: fitBlob(),
        parserVersion: kFitParserVersion + 1);
    expect(newer, ImportOutcome.refreshed);
    expect(await diveCount(), 1);
    final r = await row(c.dive.id);
    expect(r['max_depth_mm'], 77000);
    expect(r['parser_version'], kFitParserVersion + 1);
    expect(r['dc_family'], kFitDcFamily);
    expect(r['dc_fingerprint'], c.dive.dcFingerprint);
  });

  test('a Garmin Subsurface copy (decimal serial, start within 60 s) is '
      'refreshed under its own id', () async {
    final c = fitDive();
    final copy = rebuildFit(c,
        id: 'ss-copy', shiftSeconds: 30, number: 12, asSubsurfaceCopy: true);
    expect(
        await dao.importDive(
          converted: copy,
          rawBlob: Uint8List(0),
          parserVersion: kSubsurfaceImportedParserVersion,
          matchSubsurfaceCopies: false,
        ),
        ImportOutcome.inserted);

    final out = await dao.importDive(
        converted: c, rawBlob: fitBlob(), parserVersion: kFitParserVersion);

    expect(out, ImportOutcome.refreshed);
    expect(await diveCount(), 1);
    final r = await row('ss-copy');
    expect(r['dc_family'], kFitDcFamily);
    expect(r['dc_fingerprint'], c.dive.dcFingerprint);
    expect(r['parser_version'], kFitParserVersion);
    expect((await dao.getRawBlob('ss-copy'))!.sublist(0, 4), 'ALFT'.codeUnits);
    expect(await dao.getRawBlob(c.dive.id), isNull);
  });

  test('a libdivecomputer row with the same id is never written by a FIT '
      'import, raw blob included', () async {
    final c = fitDive();
    final libdc = rebuildFit(c, family: 5, fingerprint: 'aa11aa11');
    final libdcBlob = Uint8List.fromList([9, 8, 7, 6]);
    await dao.importDive(
        converted: libdc, rawBlob: libdcBlob, parserVersion: 1);
    final before = await row(c.dive.id);

    final out = await dao.importDive(
        converted: rebuildFit(c, maxDepth: 77.0),
        rawBlob: fitBlob(),
        parserVersion: kFitParserVersion + 1);

    expect(out, ImportOutcome.unchanged);
    expect(await row(c.dive.id), before);
    expect(await dao.getRawBlob(c.dive.id), libdcBlob);
  });

  test('two dives from one watch 40 s apart with dive number 0 are both '
      'stored', () async {
    final a = rebuildFit(fitDive(), number: 0);
    final b = rebuildFit(fitDive(),
        id: 'second', shiftSeconds: 40, number: 0, fingerprint: 'bb22bb22');

    expect(
        await dao.importDive(
            converted: a, rawBlob: fitBlob(), parserVersion: kFitParserVersion),
        ImportOutcome.inserted);
    expect(
        await dao.importDive(
            converted: b, rawBlob: fitBlob(), parserVersion: kFitParserVersion),
        ImportOutcome.inserted);

    expect(await diveCount(), 2);
    expect((await row('second'))['dc_fingerprint'], 'bb22bb22');
    expect((await row(a.dive.id))['dc_fingerprint'], a.dive.dcFingerprint);
  });
}
