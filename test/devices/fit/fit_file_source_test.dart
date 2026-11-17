import 'dart:io';
import 'dart:typed_data';

import 'package:ccrlogger/devices/dive_download_source.dart';
import 'package:ccrlogger/devices/fit/fit_file_source.dart';
import 'package:ccrlogger/devices/fit/fit_inputs.dart';
import 'package:fit_reader/fit_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subsurface_core/subsurface_core.dart' show kFitDcFamily;
import 'package:subsurface_core/shearwater/parser/hardware.dart';

import '../../../packages/fit_reader/test/support/fit_writer.dart';
import 'support/zip_builder.dart';

const _enumT = 0x00, _u16 = 0x84, _u32 = 0x86, _u32z = 0x8C;

FitMessageSpec _m(int g, Map<int, (int, Object)> f) => FitMessageSpec(g, f);

const _start = 1061159483;

/// A short dive file of a watch ([serial], [manufacturer]); [created]
/// distinguishes dives of one watch.
Uint8List diveFile({
  int manufacturer = 1,
  int serial = 1000000001,
  int created = _start,
  int sub = 53,
  bool withRecords = true,
}) => buildFit([
  _m(0, {
    0: (_enumT, 4),
    1: (_u16, manufacturer),
    2: (_u16, 2859),
    3: (_u32z, serial),
    4: (_u32, created),
  }),
  _m(12, {0: (_enumT, 53), 1: (_enumT, sub)}),
  if (withRecords)
    for (var i = 0; i <= 6; i++)
      _m(20, {253: (_u32, created + i), 92: (_u32, i * 1000)}),
  _m(18, {
    253: (_u32, created + 6),
    2: (_u32, created),
    5: (_enumT, 53),
    6: (_enumT, sub),
    7: (_u32, 6000),
  }),
  _m(268, {253: (_u32, created + 6), 0: (_u16, 18), 3: (_u32, 6000)}),
]);

Uint8List runFile() => buildFit([
  _m(0, {0: (_enumT, 4), 1: (_u16, 1), 3: (_u32z, 5), 4: (_u32, _start)}),
  _m(12, {0: (_enumT, 1), 1: (_enumT, 0)}),
  _m(18, {253: (_u32, _start + 60), 2: (_u32, _start), 5: (_enumT, 1)}),
]);

void main() {
  late Directory tmp;
  late Directory work;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('fit_source_test');
    work = Directory('${tmp.path}/fit-import-test');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  File put(String rel, List<int> bytes) {
    final f = File('${tmp.path}/in/$rel')..createSync(recursive: true);
    f.writeAsBytesSync(bytes);
    return f;
  }

  FitFileSource sourceOf(
    List<FitInput> inputs, [
    List<FitScanCounts>? progress,
  ]) => FitFileSource(
    inputs: inputs,
    workDir: work,
    onProgress: progress == null ? null : (c) => progress.add(c),
  );

  Uint8List fixture(String n) =>
      File('packages/fit_reader/test/fixtures/$n').readAsBytesSync();

  test('loose .fit files: dives listed, a run counted as other, a broken file '
      'as unreadable', () async {
    final mk1 = fixture('garmin_mk1_ccr_2023-08-17.fit');
    final expected = mapFitFile(mk1);
    final a = put('a.fit', mk1);
    final b = put('run.fit', runFile());
    final c = put('broken.fit', Uint8List.fromList([1, 2, 3, 4, 5]));
    final counts = <FitScanCounts>[];
    final src = sourceOf([
      FitFileInput(a.path),
      FitFileInput(b.path),
      FitFileInput(c.path),
    ], counts);
    final list = await src.listDives();
    expect(list, hasLength(expected.length));
    final d = expected.first.dive;
    final l = list.firstWhere((x) => x.diveId == d.id);
    expect(l.diveNumber, d.dcDiveNumber);
    expect(l.startTimestamp, d.startTime.millisecondsSinceEpoch ~/ 1000);
    expect(l.endTimestamp, d.endTime.millisecondsSinceEpoch ~/ 1000);
    expect(l.maxDepthMeters, d.maxDepthMeters);
    expect(l.durationSeconds, d.duration.inSeconds);
    expect(l.modelLabel, '${d.dcVendor} ${d.dcProduct}');
    expect(l.fingerprint.length, anyOf(8, 9));
    expect(
      [for (final v in l.fingerprint) v.toRadixString(16).padLeft(2, '0')]
          .join(),
      d.dcFingerprint,
    );
    final last = counts.last;
    expect(last.dives, expected.length);
    expect(last.otherActivities, 1);
    expect(last.unreadable, 1);
    expect(last.filesRead, 3);
    await src.close();
  });

  test('a Connect export zip and the same file copied off the watch give one '
      'listing', () async {
    final mk1 = fixture('garmin_mk1_ccr_2023-08-17.fit');
    final z = put(
      'export.zip',
      buildZip([ZipSpec('2023-08-17.fit', mk1, deflate: true)]),
    );
    final f = put('copy.fit', mk1);
    final src = sourceOf([FitFileInput(z.path), FitFileInput(f.path)]);
    final list = await src.listDives();
    expect(list, hasLength(mapFitFile(mk1).length));
    final events = await src.download().toList();
    final dive = events.whereType<DiveSourceDive>().first;
    expect(FitEnvelope.decode(dive.rawBlob).source, FitSource.connectExport);
    await src.close();
  });

  test('an account export (zip of a stored and a deflated inner zip) finds '
      'every dive', () async {
    final a = diveFile(created: _start);
    final b = diveFile(created: _start + 86400);
    final c = diveFile(created: _start + 2 * 86400);
    final inner1 = buildZip([ZipSpec('x/a.fit', a), ZipSpec('x/b.fit', b)]);
    final inner2 = buildZip([
      ZipSpec('c.fit', c, deflate: true),
      ZipSpec('notes.txt', Uint8List.fromList([65])),
    ]);
    final outer = put(
      'account.zip',
      buildZip([
        ZipSpec('part1.zip', inner1),
        ZipSpec('part2.zip', inner2, deflate: true),
      ]),
    );
    final counts = <FitScanCounts>[];
    final src = sourceOf([FitFileInput(outer.path)], counts);
    final list = await src.listDives();
    expect(list, hasLength(3));
    expect(list.map((e) => e.startTimestamp).toList(), [
      for (final t in [_start + 2 * 86400, _start + 86400, _start])
        t + 631065600,
    ]);
    final events = await src.download().toList();
    final blobs = events.whereType<DiveSourceDive>().toList();
    expect(blobs, hasLength(3));
    expect(
      FitEnvelope.decode(blobs.first.rawBlob).source,
      FitSource.accountExport,
    );
    expect(counts.last.dives, 3);
    await src.close();
    expect(work.existsSync(), isFalse);
  });

  test('a folder is read recursively', () async {
    put('d/one.fit', diveFile(created: _start));
    put('d/sub/two.FIT', diveFile(created: _start + 1000));
    put('d/sub/readme.txt', [1, 2]);
    final src = sourceOf([FitFolderInput('${tmp.path}/in/d')]);
    expect(await src.listDives(), hasLength(2));
    final events = await src.download().toList();
    expect(
      FitEnvelope.decode(events.whereType<DiveSourceDive>().first.rawBlob)
          .source,
      FitSource.folder,
    );
    await src.close();
  });

  test('apnea sessions are counted and not listed', () async {
    final f = put('apnea.fit', diveFile(sub: 56));
    final counts = <FitScanCounts>[];
    final src = sourceOf([FitFileInput(f.path)], counts);
    expect(await src.listDives(), isEmpty);
    expect(counts.last.apnea, 1);
    expect(counts.last.dives, 0);
    await src.close();
  });

  test('progress counts reach their totals', () async {
    final z = put(
      'e.zip',
      buildZip([
        ZipSpec('a.fit', diveFile(created: _start)),
        ZipSpec('b.fit', diveFile(created: _start + 5000)),
      ]),
    );
    final f = put('c.fit', diveFile(created: _start + 9000));
    final counts = <FitScanCounts>[];
    final src = sourceOf([FitFileInput(z.path), FitFileInput(f.path)], counts);
    await src.listDives();
    expect(counts.last.filesRead, 3);
    expect(counts.last.filesTotal, 3);
    for (final c in counts) {
      expect(c.filesRead, lessThanOrEqualTo(c.filesTotal ?? 1 << 30));
    }
    await src.close();
  });

  test('download announces each watch before its dives and emits ALFT blobs',
      () async {
    final f = put('a.fit', diveFile());
    final src = sourceOf([FitFileInput(f.path)]);
    final list = await src.listDives();
    final events = await src.download(selection: list).toList();
    expect(events.first, isA<DiveSourceIdentified>());
    final id = (events.first as DiveSourceIdentified).identity;
    expect(id.vendor, 'Garmin');
    expect(id.serial, 1000000001);
    expect(id.family, kFitDcFamily);
    expect(id.dcModel, ShearwaterModel.unknown);
    expect(id.computerModel, 0);
    expect(id.importStateKey, 'fit:1:1000000001');
    expect(id.serialLabel, '1000000001');
    expect(id.modelLabel, startsWith('Garmin '));
    expect(id.firmwareLabel, '');
    expect(src.identity, same(id));
    final dive = events.whereType<DiveSourceDive>().single;
    expect(dive.parserVersion, kFitParserVersion);
    expect(dive.rawBlob.sublist(0, 4), [0x41, 0x4C, 0x46, 0x54]);
    expect(dive.converted.dive.id, list.single.diveId);
    expect(events.whereType<DiveSourceProgress>(), hasLength(1));
    final fin = events.last as DiveSourceFinished;
    expect(fin.importStateKey, 'fit:1:1000000001');
    expect(fin.fingerprintToKeep, isNull);
    expect(fin.recordingText, isNull);
    await src.close();
  });

  test('progress events count dives from 0, like the other engines',
      () async {
    final a = put('a.fit', diveFile(created: _start));
    final b = put('b.fit', diveFile(created: _start + 100000));
    final src = sourceOf([FitFileInput(a.path), FitFileInput(b.path)]);
    final list = await src.listDives();
    final events = await src.download(selection: list).toList();
    final progress = events.whereType<DiveSourceProgress>().toList();
    expect([for (final e in progress) e.diveIndex], [0, 1]);
    expect(progress.every((e) => e.totalDives == 2), isTrue);
    await src.close();
  });

  test('a session without samples is a failed dive', () async {
    final f = put('a.fit', diveFile(withRecords: false));
    final src = sourceOf([FitFileInput(f.path)]);
    expect(await src.listDives(), hasLength(1));
    final events = await src.download().toList();
    expect(events.whereType<DiveSourceDiveFailed>(), hasLength(1));
    expect(events.whereType<DiveSourceDive>(), isEmpty);
    await src.close();
  });

  test('two watches in one pick give two identities', () async {
    final a = put('a.fit', diveFile(serial: 11, created: _start));
    final b = put('b.fit', diveFile(serial: 22, created: _start + 100));
    final c = put('c.fit', diveFile(serial: 11, created: _start + 90000));
    final src = sourceOf([
      FitFileInput(a.path),
      FitFileInput(b.path),
      FitFileInput(c.path),
    ]);
    await src.listDives();
    final events = await src.download().toList();
    final ids = events.whereType<DiveSourceIdentified>().toList();
    expect(ids.map((e) => e.identity.serial).toList(), [11, 22]);
    final seq = [
      for (final e in events)
        if (e is DiveSourceIdentified)
          'id${e.identity.serial}'
        else if (e is DiveSourceDive)
          'dive',
    ];
    expect(seq, ['id11', 'dive', 'dive', 'id22', 'dive']);
    expect((events.last as DiveSourceFinished).importStateKey, 'fit:1:22');
    await src.close();
  });

  test('close deletes the work folder; purgeStaleFitWorkDirs removes '
      'leftovers', () async {
    final f = put('a.fit', diveFile());
    final src = sourceOf([FitFileInput(f.path)]);
    await src.listDives();
    expect(work.existsSync(), isTrue);
    await src.close();
    expect(work.existsSync(), isFalse);
    await src.close();

    Directory('${tmp.path}/fit-import-old/dives').createSync(recursive: true);
    Directory('${tmp.path}/other').createSync();
    await purgeStaleFitWorkDirs(tmp);
    expect(Directory('${tmp.path}/fit-import-old').existsSync(), isFalse);
    expect(Directory('${tmp.path}/other').existsSync(), isTrue);
  });

  test('cancelling the download subscription leaves committed dives and '
      'close still cleans up', () async {
    final a = put('a.fit', diveFile(created: _start));
    final b = put('b.fit', diveFile(created: _start + 100));
    final src = sourceOf([FitFileInput(a.path), FitFileInput(b.path)]);
    await src.listDives();
    final got = <DiveSourceEvent>[];
    await for (final e in src.download()) {
      got.add(e);
      if (e is DiveSourceDive) break;
    }
    expect(got.whereType<DiveSourceDive>(), hasLength(1));
    await src.close();
    expect(work.existsSync(), isFalse);
  });

  test('an unlistable subfolder does not discard the rest of the folder',
      () async {
    put('d/ok.fit', diveFile());
    final locked = Directory('${tmp.path}/in/d/locked')..createSync();
    File('${locked.path}/x.fit').writeAsBytesSync(diveFile(created: 5));
    Process.runSync('chmod', ['000', locked.path]);
    addTearDown(() => Process.runSync('chmod', ['755', locked.path]));
    final src = sourceOf([FitFolderInput('${tmp.path}/in/d')]);
    final counts = <FitScanCounts>[];
    final src2 = FitFileSource(
      inputs: [FitFolderInput('${tmp.path}/in/d')],
      workDir: work,
      onProgress: counts.add,
    );
    expect(await src.listDives(), hasLength(1));
    await src.close();
    await src2.listDives();
    expect(counts.last.unreadable, 1);
    expect(counts.last.filesRead, 2);
    await src2.close();
  },
      skip: Platform.isWindows || Process.runSync('id', ['-u']).stdout
              .toString()
              .trim() ==
          '0'
          ? 'chmod is not reliable here'
          : false);

  test('close during a running scan removes the work folder and listDives '
      'finishes', () async {
    for (var i = 0; i < 6; i++) {
      put('c$i.fit', diveFile(created: _start + i * 1000));
    }
    final src = sourceOf([FitFolderInput('${tmp.path}/in')]);
    final listing = src.listDives();
    await Future<void>.delayed(Duration.zero);
    await src.close();
    await listing;
    expect(work.existsSync(), isFalse);
  });

  test('the watch firmware is the newest dive\'s', () async {
    Uint8List withFirmware(int created, int fw) {
      final base = diveFile(created: created);
      final f = readFitDives(base);
      expect(f.sessions, hasLength(1));
      return buildFit([
        _m(0, {
          0: (_enumT, 4),
          1: (_u16, 1),
          2: (_u16, 2859),
          3: (_u32z, 1000000001),
          4: (_u32, created),
        }),
        _m(23, {253: (_u32, created), 0: (_enumT, 0), 5: (_u32, fw)}),
        _m(12, {0: (_enumT, 53), 1: (_enumT, 53)}),
        for (var i = 0; i <= 6; i++)
          _m(20, {253: (_u32, created + i), 92: (_u32, i * 1000)}),
        _m(18, {
          253: (_u32, created + 6),
          2: (_u32, created),
          5: (_enumT, 53),
          6: (_enumT, 53),
          7: (_u32, 6000),
        }),
        _m(268, {253: (_u32, created + 6), 0: (_u16, 18), 3: (_u32, 6000)}),
      ]);
    }

    final a = put('old.fit', withFirmware(_start, 1000));
    final b = put('new.fit', withFirmware(_start + 86400, 1234));
    final src = sourceOf([FitFileInput(b.path), FitFileInput(a.path)]);
    await src.listDives();
    final events = await src.download().toList();
    final id = events.whereType<DiveSourceIdentified>().single.identity;
    expect(id.firmware, 1234);
    expect(id.firmwareLabel, '12.34');
    await src.close();
  });

  test('a dive file without any dive session counts as unreadable', () async {
    final f = put(
      'empty.fit',
      buildFit([
        _m(0, {0: (_enumT, 4), 1: (_u16, 1), 3: (_u32z, 7), 4: (_u32, 5)}),
        _m(12, {0: (_enumT, 53), 1: (_enumT, 53)}),
      ]),
    );
    final counts = <FitScanCounts>[];
    final src = sourceOf([FitFileInput(f.path)], counts);
    expect(await src.listDives(), isEmpty);
    expect(counts.last.unreadable, 1);
    expect(counts.last.filesRead, 1);
    await src.close();
  });
}
