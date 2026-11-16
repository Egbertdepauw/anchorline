// A real Subsurface Cloud copy of eight Petrel 3 dives, then a replay of
// the Petrel 3 download of the same dives. The copies must be refreshed in
// place: no duplicates, the copy's own id and start time, the download's
// data, and every piece of user data untouched.

import 'dart:io';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/devices/dive_download_source.dart';
import 'package:ccrlogger/devices/shearwater/shearwater_download_source.dart';
import 'package:ccrlogger/shearwater/ble/shearwater_ble_transport.dart';
import 'package:ccrlogger/sync/subsurface_git/bootstrap_importer.dart';
import 'package:ccrlogger/sync/subsurface_git/credentials.dart';
import 'package:ccrlogger/sync/subsurface_git/repo.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:powersync/powersync.dart';
import 'package:subsurface_core/data/models/annotation.dart' show Patch;
import 'package:subsurface_core/data/sample_codec/sample_codec.dart';
import 'package:subsurface_core/subsurface_core.dart'
    show kSubsurfaceImportedParserVersion;
import 'package:ccrlogger/shearwater/parser/parser_version.dart';

import '../../_helpers/powersync_test_helper.dart';
import '../../shearwater/ble/protocol_test.dart' show TraceMockBle;

const _fixtureRoot = 'test/fixtures/subsurface_petrel3';
const _email = 'tester@example.com';

class _Credentials implements SubsurfaceCredentialsSource {
  @override
  Future<({String email, String password})?> read() async =>
      (email: _email, password: 'pw');
  @override
  Future<void> save(String email, String password) async =>
      throw UnimplementedError();
  @override
  Future<void> clear() async => throw UnimplementedError();
}

/// A repo whose git actions do nothing; the importer reads the clone
/// directory straight from disk.
class _FakeRepo extends SubsurfaceRepo {
  _FakeRepo({
    required super.localDir,
    required super.remoteUrl,
    required super.credentials,
  });
  @override
  Future<void> ensureCloned() async {}
  @override
  Future<void> pull() async {}
}

/// Copies the fixture into the layout the importer reads:
/// `<root>/<email>-bootstrap/{YYYY/MM/<dive>, 01-Divesites/Site-x}`.
Directory _cloneRootWithFixture() {
  final root = Directory.systemTemp.createTempSync('ccrlog_petrel3_');
  addTearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
  final clone = Directory(p.join(root.path, '$_email-bootstrap'))
    ..createSync(recursive: true);
  void copyDir(Directory from, Directory to) {
    to.createSync(recursive: true);
    for (final e in from.listSync()) {
      if (e is File) e.copySync(p.join(to.path, p.basename(e.path)));
      if (e is Directory) copyDir(e, Directory(p.join(to.path, p.basename(e.path))));
    }
  }

  for (final year in Directory('$_fixtureRoot/dives').listSync()) {
    copyDir(year as Directory,
        Directory(p.join(clone.path, p.basename(year.path))));
  }
  copyDir(Directory('$_fixtureRoot/sites'),
      Directory(p.join(clone.path, '01-Divesites')));
  // Shift one copy's start by +7 s. The importer takes a dive's start from
  // its folder name alone, so renaming the folder is the whole shift.
  Directory(p.join(clone.path, '2026', '04', '04-Sat-13=30=15'))
      .renameSync(p.join(clone.path, '2026', '04', '04-Sat-13=30=22'));
  File('$_fixtureRoot/00-Subsurface')
      .copySync(p.join(clone.path, '00-Subsurface'));
  return root;
}

Future<ShearwaterDownloadSource> _openTraceSource() {
  // The recorded trace is strictly sequential, replay it that way.
  final t = ShearwaterBleTransport(divePipelineWindow: 1)
    ..connectWithIo(TraceMockBle('test/fixtures/raw/subsurface2.combined.txt'));
  return ShearwaterDownloadSource.open(t);
}

/// The trace holds the raw blobs of its eight newest dives, #711-#718.
Future<List<DiveSourceDive>> _downloadAll() async {
  final source = await _openTraceSource();
  final listings = await source.listDives();
  final events =
      await source.download(selection: listings.take(8).toList()).toList();
  await source.close();
  return events.whereType<DiveSourceDive>().toList();
}

void main() {
  late AppDatabase db;
  late DiveDaoTestRig rig;
  late DiveDao dao;
  late PowerSyncDatabase ps;
  late DiveAnnotationsDao annotations;
  late EquipmentDao equipment;
  late Directory cloneRoot;
  late SubsurfaceBootstrapImporter importer;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    rig = await openDiveDaoForTest(db);
    dao = rig.dao;
    ps = rig.ps;
    annotations = DiveAnnotationsDao(ps, rig.session);
    equipment = EquipmentDao(db, ps, rig.session);
    cloneRoot = _cloneRootWithFixture();
    importer = SubsurfaceBootstrapImporter(
      credentials: _Credentials(),
      localCloneRoot: cloneRoot,
      dataSource:
          DaoBootstrapDataSource(diveDao: dao, annotationsDao: annotations),
      repoFactory: ({
        required Directory localDir,
        required String remoteUrl,
        required SubsurfaceCredentialsSource credentials,
      }) =>
          _FakeRepo(
              localDir: localDir,
              remoteUrl: remoteUrl,
              credentials: credentials),
    );
  });
  tearDown(() => db.close());

  Future<int> bootstrap() async {
    final events = await importer.import().toList();
    final done = events.last;
    expect(done, isA<BootstrapDone>(), reason: '$done');
    return (done as BootstrapDone).result.divesImported;
  }

  Future<List<Map<String, dynamic>>> diveRows() async => [
        for (final r in await ps
            .getAll('SELECT * FROM dives WHERE deleted_at IS NULL ORDER BY start_time'))
          Map<String, dynamic>.of(r)
      ];

  Future<int> bootstrapAndAddUserData() async {
    expect(await bootstrap(), 8);
    final rows = await diveRows();
    final id = rows.first['id'] as String;
    final ann = (await annotations.get(id))!;
    await annotations.upsert(
        ann.copyWith(notes: const Patch('my own note'), buddies: ['Test Buddy']));
    await ps.execute(
        'INSERT INTO dive_bailout_carry (id, owner_id, dive_id, version) '
        "VALUES ('bo1', 'test-user', ?, 1)",
        [id]);
    await equipment.setDiveCylinders(id, [
      (gasMixIndex: 0, cylinderId: 'cylA'),
    ]);
    return rows.length;
  }

  test(
      'download after bootstrap: no duplicates, copies refreshed under their '
      'ids, user data kept', () async {
    await bootstrapAndAddUserData();
    final before = await diveRows();
    expect(before, hasLength(8));
    for (final r in before) {
      expect(r['parser_version'], kSubsurfaceImportedParserVersion);
    }
    final userIdBefore = before.first['id'] as String;
    final annBefore = (await annotations.get(userIdBefore))!;
    final bailoutBefore =
        (await ps.getAll('SELECT * FROM dive_bailout_carry')).map(Map.of).toList();
    final cylBefore = await equipment.listCylindersForDive(userIdBefore);
    expect(cylBefore, hasLength(1));

    int startOf(DiveSourceDive d) =>
        d.converted.dive.startTime.millisecondsSinceEpoch ~/ 1000;
    final downloaded = await _downloadAll();
    expect(downloaded, hasLength(8));
    final outcomes = <ImportOutcome>[];
    for (final d in downloaded) {
      outcomes.add(await dao.importDive(
        converted: d.converted,
        rawBlob: d.rawBlob,
        parserVersion: d.parserVersion,
      ));
    }
    expect(outcomes, everyElement(ImportOutcome.refreshed));

    // The shifted copy (dive #714 in the trace) started 7 s after the trace.
    final shifted = downloaded
        .singleWhere((d) => d.converted.dive.dcDiveNumber == 714);
    final shiftedBefore = before.singleWhere(
        (r) => r['start_time'] == startOf(shifted) + 7);
    final shiftedAfter = (await diveRows())
        .singleWhere((r) => r['id'] == shiftedBefore['id']);
    expect(shiftedAfter['start_time'], startOf(shifted) + 7);
    expect(outcomes[downloaded.indexOf(shifted)], ImportOutcome.refreshed);

    final after = await diveRows();
    expect(after, hasLength(8), reason: 'no duplicates');
    expect([for (final r in after) r['id']], [for (final r in before) r['id']]);
    for (var i = 0; i < before.length; i++) {
      final b = before[i];
      final a = after[i];
      // Subsurface Cloud identifies a pushed dive by (serial, start_time).
      expect(a['start_time'], b['start_time']);
      expect(a['parser_version'], kShearwaterParserVersion);
      expect(a['dc_serial'], b['dc_serial']);
    }

    // Each copy took the data of the download that matches its start time.
    for (final a in after) {
      final d = downloaded.singleWhere(
          (d) => (startOf(d) - (a['start_time'] as int)).abs() <= 60);
      final id = a['id'] as String;
      expect(await dao.getRawBlob(id), d.rawBlob);
      expect(a['dc_dive_number'], d.converted.dive.dcDiveNumber);
      final stored = SampleCodec.encode((await dao.getSamples(id))!);
      final fresh = SampleCodec.encode(d.converted.samples);
      expect(stored.keys, fresh.keys);
      for (final k in fresh.keys) {
        expect(stored[k], fresh[k], reason: 'column $k of $id');
      }
    }

    // User data survives.
    final annAfter = (await annotations.get(userIdBefore))!;
    expect(annAfter.notes, 'my own note');
    expect(annAfter.buddies, ['Test Buddy']);
    expect(annAfter.tags, annBefore.tags);
    expect(annAfter.siteName, annBefore.siteName);
    expect(
        (await ps.getAll('SELECT * FROM dive_bailout_carry')).map(Map.of).toList(),
        bailoutBefore);
    final cylAfter = await equipment.listCylindersForDive(userIdBefore);
    expect([for (final c in cylAfter) c.cylinderId], ['cylA']);
  });

  test('refreshed copies are not offered as new on the next scan', () async {
    await bootstrap();
    // The scan's listings, one per downloaded dive. The trace replays its
    // blobs in the order they were recorded, not the order requested, so a
    // blob's own number and start (what the stored dive carries) are the
    // coherent pair; the manifest's pairing differs for this trace only.
    final downloaded = await _downloadAll();
    final listings = [
      for (final d in downloaded)
        (
          diveId: d.converted.dive.id,
          startTimestamp:
              d.converted.dive.startTime.millisecondsSinceEpoch ~/ 1000,
          diveNumber: d.converted.dive.dcDiveNumber,
        )
    ];
    Future<Set<String>> hidden() => dao.alreadyDownloadedAmong(
          [
            for (final l in listings)
              (
                diveId: l.diveId,
                startTimeSeconds: l.startTimestamp,
                diveNumber: l.diveNumber,
              )
          ],
          vendor: 'Shearwater',
          serial: 0xB89641E4,
        );

    expect(await hidden(), isEmpty, reason: 'copies only, still at -1');

    for (final d in downloaded) {
      await dao.importDive(
        converted: d.converted,
        rawBlob: d.rawBlob,
        parserVersion: d.parserVersion,
      );
    }
    expect(await hidden(), hasLength(8));
    expect(await hidden(), {for (final l in listings) l.diveId});
  });

  test('downloading everything again changes nothing', () async {
    await bootstrap();
    for (final d in await _downloadAll()) {
      await dao.importDive(
        converted: d.converted,
        rawBlob: d.rawBlob,
        parserVersion: d.parserVersion,
      );
    }
    final before = await diveRows();

    final outcomes = <ImportOutcome>[];
    for (final d in await _downloadAll()) {
      outcomes.add(await dao.importDive(
        converted: d.converted,
        rawBlob: d.rawBlob,
        parserVersion: d.parserVersion,
      ));
    }

    expect(outcomes, hasLength(8));
    expect(outcomes, everyElement(ImportOutcome.unchanged));
    expect(await diveRows(), before);
  });

  test('a bootstrap after the downloads imports nothing', () async {
    await bootstrap();
    for (final d in await _downloadAll()) {
      await dao.importDive(
        converted: d.converted,
        rawBlob: d.rawBlob,
        parserVersion: d.parserVersion,
      );
    }
    final before = await diveRows();

    expect(await bootstrap(), 0);
    expect(await diveRows(), before);
  });
}
