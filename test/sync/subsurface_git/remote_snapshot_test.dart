// Tests for RemoteSnapshot — the read-from-disk side of Phase D's
// orchestration. We mirror the test/fixtures/subsurface tree into a
// temp directory and assert that the snapshot extracts the right
// fields from it.

@TestOn('mac-os || linux || windows')
library;

import 'dart:io';

import 'package:ccrlogger/sync/subsurface_git/format/subsurface_format.dart';
import 'package:ccrlogger/sync/subsurface_git/remote_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _fixturesRoot = 'test/fixtures/subsurface';

void main() {
  group('RemoteSnapshot.read', () {
    late Directory tmp;

    setUp(() {
      // Build a canonical Subsurface repo layout from the fixtures.
      // The fixtures themselves are organised as
      //   <fixtures>/00-Subsurface
      //   <fixtures>/sites/Site-*
      //   <fixtures>/dives/<YYYY>/<MM>/<DD-Day-...>/{Dive-*, Divecomputer}
      // — but a real repo has Site-* under `01-Divesites/` and dives
      // directly under `<YYYY>/...`. We materialise the canonical
      // layout into [tmp] so the snapshot reader sees a real-shaped
      // repo.
      tmp = Directory.systemTemp.createTempSync('ccrlog_snap_');
      // 00-Subsurface
      File('$_fixturesRoot/00-Subsurface').copySync('${tmp.path}/00-Subsurface');
      // 01-Divesites/
      final sitesDst = Directory('${tmp.path}/01-Divesites')..createSync();
      for (final f in Directory('$_fixturesRoot/sites').listSync()) {
        if (f is File) {
          f.copySync('${sitesDst.path}/${p.basename(f.path)}');
        }
      }
      // <YYYY>/<MM>/<DD>/
      _copyDirectory(Directory('$_fixturesRoot/dives'), tmp);
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('existingMaxDiveNumber matches the highest Dive-NNN seen', () async {
      final snap = await RemoteSnapshot.read(tmp);
      // Fixture set has Dive-13, Dive-365, Dive-656, Dive-705, Dive-710.
      expect(snap.existingMaxDiveNumber, 710);
    });

    test('existingDivesBySerialAndStart includes the modern Petrel '
        'entries keyed correctly', () async {
      final snap = await RemoteSnapshot.read(tmp);

      // 2026/04/04-Sat-13=30=15 → 2026-04-04T13:30:15Z UTC.
      final t1 = DateTime.utc(2026, 04, 04, 13, 30, 15)
              .millisecondsSinceEpoch ~/
          1000;
      expect(
        snap.existingDivesBySerialAndStart
            .containsKey((serial: 0xb89641e4, startTime: t1)),
        isTrue,
        reason: 'expected modern Petrel 3 dive at 2026-04-04 13:30:15Z',
      );
      final dive1 = snap.existingDivesBySerialAndStart[
          (serial: 0xb89641e4, startTime: t1)]!;
      expect(dive1.diveNumber, 705);
      expect(dive1.folderSegments, ['2026', '04', '04-Sat-13=30=15']);

      // 2026/04/27-Mon-11=33=43.
      final t2 = DateTime.utc(2026, 04, 27, 11, 33, 43)
              .millisecondsSinceEpoch ~/
          1000;
      expect(
        snap.existingDivesBySerialAndStart
            .containsKey((serial: 0xb89641e4, startTime: t2)),
        isTrue,
        reason: 'expected modern Petrel 3 dive at 2026-04-27 11:33:43Z',
      );
      final dive2 = snap.existingDivesBySerialAndStart[
          (serial: 0xb89641e4, startTime: t2)]!;
      expect(dive2.diveNumber, 710);
    });

    test('existingTopLevel parses the fixture 00-Subsurface', () async {
      final snap = await RemoteSnapshot.read(tmp);
      expect(snap.existingTopLevel, isNotEmpty);

      // First non-blank line is `version 3`.
      final firstScalar =
          snap.existingTopLevel.whereType<ScalarLine>().first;
      expect(firstScalar.key, 'version');
      expect(firstScalar.value, '3');

      // The fixture has multiple divecomputerid + fingerprint lines.
      expect(
        snap.existingTopLevel.whereType<DivecomputerIdLine>().length,
        greaterThanOrEqualTo(2),
      );
      expect(
        snap.existingTopLevel.whereType<FingerprintLine>().length,
        greaterThanOrEqualTo(3),
      );
    });

    test('existingSites is keyed by hex id and parses each site',
        () async {
      final snap = await RemoteSnapshot.read(tmp);
      // Fixtures: Site-0a9f7232, Site-0acb7fe3, Site-ecaf8184.
      expect(snap.existingSites.keys.toSet(),
          {'0a9f7232', '0acb7fe3', 'ecaf8184'});

      final omSid = snap.existingSites['0a9f7232']!;
      // Has a `name` quoted line, a `gps` line, and a `geo` line.
      final nameLine = omSid.whereType<QuotedLine>().firstWhere(
            (l) => l.key == 'name',
          );
      expect(nameLine.value, 'Om Sid - Dahab');
      expect(omSid.whereType<GpsLine>().single.lat, '28.420550');
    });

    test('returns empty snapshot when repoRoot does not exist', () async {
      final missing = Directory('${tmp.path}/does-not-exist');
      final snap = await RemoteSnapshot.read(missing);
      expect(snap.existingTopLevel, isEmpty);
      expect(snap.existingSites, isEmpty);
      expect(snap.existingDivesBySerialAndStart, isEmpty);
      expect(snap.existingMaxDiveNumber, 0);
    });

    test('skips folders whose names do not match the date format', () async {
      // Drop a stray top-level folder; it must not appear in the snapshot
      // and must not break the walk.
      Directory('${tmp.path}/.git').createSync();
      File('${tmp.path}/.git/HEAD').writeAsStringSync('ref: refs/heads/x\n');
      Directory('${tmp.path}/junk').createSync();

      final snap = await RemoteSnapshot.read(tmp);
      // Original max stays at 710 — we didn't add any real dive folders.
      expect(snap.existingMaxDiveNumber, 710);
    });
  });
}

void _copyDirectory(Directory src, Directory dst) {
  for (final entity in src.listSync(recursive: true)) {
    final relPath = p.relative(entity.path, from: src.path);
    final targetPath = p.join(dst.path, relPath);
    if (entity is Directory) {
      Directory(targetPath).createSync(recursive: true);
    } else if (entity is File) {
      Directory(p.dirname(targetPath)).createSync(recursive: true);
      entity.copySync(targetPath);
    }
  }
}
