// Tests for RemoteSnapshot.fromFiles — the pure builder behind Phase D's
// orchestration. We feed it the test/fixtures/subsurface tree, re-keyed
// into the canonical repo layout, and assert that the snapshot extracts
// the right fields from it.

@TestOn('mac-os || linux || windows')
library;

import 'dart:io';

import 'package:subsurface_core/sync/subsurface_git/format/subsurface_format.dart';
import 'package:subsurface_core/sync/subsurface_git/remote_snapshot.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

const _fixturesRoot = 'test/fixtures/subsurface';

// The fixtures are organised as
//   <fixtures>/00-Subsurface
//   <fixtures>/sites/Site-*
//   <fixtures>/dives/<YYYY>/<MM>/<DD-Day-...>/{Dive-*, Divecomputer}
// — but a real repo has Site-* under `01-Divesites/` and dives directly
// under `<YYYY>/...`. This re-keys them into that canonical layout, as
// POSIX paths relative to the repo root.
Map<String, String> _fixtureFiles() => {
      '00-Subsurface': File('$_fixturesRoot/00-Subsurface').readAsStringSync(),
      for (final f
          in Directory('$_fixturesRoot/sites').listSync().whereType<File>())
        '01-Divesites/${p.basename(f.path)}': f.readAsStringSync(),
      for (final f in Directory('$_fixturesRoot/dives')
          .listSync(recursive: true)
          .whereType<File>())
        p.posix.joinAll(
                p.split(p.relative(f.path, from: '$_fixturesRoot/dives'))):
            f.readAsStringSync(),
    };

void main() {
  group('RemoteSnapshot.fromFiles', () {
    test('existingMaxDiveNumber matches the highest Dive-NNN seen', () {
      final snap = RemoteSnapshot.fromFiles(_fixtureFiles());
      // Fixture set has Dive-13, Dive-365, Dive-656, Dive-705, Dive-710.
      expect(snap.existingMaxDiveNumber, 710);
    });

    test('existingDivesBySerialAndStart includes the modern Petrel '
        'entries keyed correctly', () {
      final snap = RemoteSnapshot.fromFiles(_fixtureFiles());

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

    test('existingTopLevel parses the fixture 00-Subsurface', () {
      final snap = RemoteSnapshot.fromFiles(_fixtureFiles());
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

    test('existingSites is keyed by hex id and parses each site', () {
      final snap = RemoteSnapshot.fromFiles(_fixtureFiles());
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

    test('returns empty snapshot when there are no files', () {
      final snap = RemoteSnapshot.fromFiles(const {});
      expect(snap.existingTopLevel, isEmpty);
      expect(snap.existingSites, isEmpty);
      expect(snap.existingDivesBySerialAndStart, isEmpty);
      expect(snap.existingMaxDiveNumber, 0);
    });

    test('skips folders whose names do not match the date format', () {
      // Stray `.git` and top-level folder contents must not appear in the
      // snapshot and must not break the build.
      final baseline = RemoteSnapshot.fromFiles(_fixtureFiles());
      final files = _fixtureFiles()
        ..['.git/HEAD'] = 'ref: refs/heads/x\n'
        ..['junk/Dive-999'] = 'duration 1:00 min\n';

      final snap = RemoteSnapshot.fromFiles(files);
      // Original max stays at 710 — we didn't add any real dive folders.
      expect(snap.existingMaxDiveNumber, 710);
      expect(snap.existingDivesBySerialAndStart.length,
          baseline.existingDivesBySerialAndStart.length);
    });

    test('scan parses existing Dive-NNN files and attaches diveLines', () {
      final snap = RemoteSnapshot.fromFiles(_fixtureFiles());
      expect(snap.existingDivesBySerialAndStart, isNotEmpty);
      final any = snap.existingDivesBySerialAndStart.values.first;
      expect(any.diveLines, isNotEmpty,
          reason: 'fromFiles should populate diveLines from the Dive-NNN');
      // A Dive-NNN always carries a `duration` scalar; verify it parsed.
      expect(
        any.diveLines.whereType<ScalarLine>().any((l) => l.key == 'duration'),
        isTrue,
      );
    });

    test('bare Divecomputer wins over Divecomputer-NNN whatever the map order',
        () {
      final folder = '2026/04/04-Sat-13=30=15';
      final bare =
          File('$_fixturesRoot/dives/$folder/Divecomputer').readAsStringSync();
      final files = {
        '$folder/Divecomputer-001': 'model "Other"\nkeyvalue "Serial" "00000001"\n',
        '$folder/Divecomputer': bare,
        '$folder/Dive-705':
            File('$_fixturesRoot/dives/$folder/Dive-705').readAsStringSync(),
      };
      final snap = RemoteSnapshot.fromFiles(files);
      final t = DateTime.utc(2026, 4, 4, 13, 30, 15).millisecondsSinceEpoch ~/
          1000;
      expect(snap.existingDivesBySerialAndStart.keys.single,
          (serial: 0xb89641e4, startTime: t));
    });
  });
}
