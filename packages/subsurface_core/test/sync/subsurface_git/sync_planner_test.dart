// Pure-Dart tests for the Phase D sync planner.
//
// The planner is the load-bearing piece of the orchestrator's pure
// half: walking CCRLog state plus a parsed remote-repo snapshot and
// emitting the exact set of file writes to perform. These tests build
// the inputs in memory and assert on the plan's outputs without
// touching disk, git, PowerSync, or the real DAOs. The orchestrator's
// own end-to-end tests live in `sync_orchestrator_test.dart`.

@TestOn('mac-os || linux || windows')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:subsurface_core/data/models/annotation.dart';
import 'package:subsurface_core/data/models/dive.dart' show DiveGasMix;
import 'package:subsurface_core/data/models/sample_set.dart';
import 'package:subsurface_core/sync/subsurface_git/format/subsurface_format.dart';
import 'package:subsurface_core/sync/subsurface_git/format/subsurface_parser.dart';
import 'package:subsurface_core/sync/subsurface_git/mapper.dart';
import 'package:subsurface_core/sync/subsurface_git/remote_snapshot.dart';
import 'package:subsurface_core/sync/subsurface_git/sync_inputs.dart';
import 'package:subsurface_core/sync/subsurface_git/sync_planner.dart';
import 'package:test/test.dart';

void main() {
  group('SyncPlanner.plan', () {
    test('new dive (no remote match) emits Dive-NNN + Divecomputer at '
        'allocated path', () {
      final planner = SyncPlanner();
      final bundle = _bundle(diveId: _diveIdA);
      final plan = planner.plan(
        ccrlogDives: [bundle],
        existingDivesBySerialAndStart: const {},
        existingMaxDiveNumber: 100,
        existingTopLevel: const [],
        existingSites: const {},
      );

      // 1776611925 = 2026-04-19T15:18:45Z (UTC).
      // The planner now prefers the dive computer's own number (705 in
      // the fixture) over max+1 when it's not already taken in the
      // remote — keeps Subsurface's numbering aligned with CCRLog.
      expect(
        plan.filesToWrite.keys,
        containsAll([
          '2026/04/19-Sun-15=18=45/Dive-705',
          '2026/04/19-Sun-15=18=45/Divecomputer',
        ]),
      );
      expect(plan.diveIdsPlanned, [_diveIdA]);
      expect(plan.stats.newDives, 1);
      expect(plan.stats.updatedDives, 0);

      // Dive file content has expected fields.
      final diveText =
          plan.filesToWrite['2026/04/19-Sun-15=18=45/Dive-705']!;
      expect(diveText, contains('duration 57:30 min'));

      final dcText =
          plan.filesToWrite['2026/04/19-Sun-15=18=45/Divecomputer']!;
      expect(dcText, startsWith('model "Shearwater Petrel 3"'));
    });

    test('existing dive (matching serial, startTime) reuses folder + NNN',
        () {
      final planner = SyncPlanner();
      // gasMixes: const [] so the mapper doesn't emit cylinder lines that
      // would conflict with the existing fixture's single cylinder.
      // annotation: rating differs from existing so the merge produces
      // a different file and updatedDives = 1.
      final bundle = _bundle(
        diveId: _diveIdA,
        gasMixes: const [],
        annotation: _testAnnotation(rating: 5),
      );
      // A minimally-realistic on-disk Dive-NNN — non-empty diveLines is a
      // precondition for the merge path (empty triggers the unreadable
      // abort case, covered by its own test below).
      final existingLines = parseSubsurfaceFile(
        'duration 57:30 min\n'
        'rating 2\n'
        'divemaster ""\n'
        'buddy ""\n'
        'suit ""\n',
        kind: SubsurfaceFileKind.dive,
      ).lines;
      final existing = ExistingRemoteDive(
        folderSegments: ['2026', '04', '04-Sat-13=18=45'],
        diveNumber: 705,
        serial: 0xb89641e4,
        startTime: 1776611925,
        diveLines: existingLines,
      );
      final plan = planner.plan(
        ccrlogDives: [bundle],
        existingDivesBySerialAndStart: {
          (serial: 0xb89641e4, startTime: 1776611925): existing,
        },
        existingMaxDiveNumber: 800, // would otherwise allocate 801
        existingTopLevel: const [],
        existingSites: const {},
      );

      // Phase 1 semantics: existing dive's Dive-NNN may be written (with
      // merged content) but Divecomputer is NEVER written for an existing
      // dive — the DC's sample stream is sacred.
      expect(
        plan.filesToWrite.keys,
        contains('2026/04/04-Sat-13=18=45/Dive-705'),
      );
      expect(
        plan.filesToWrite.keys
            .where((k) => k.endsWith('/Divecomputer'))
            .toList(),
        isEmpty,
      );
      // Did NOT allocate Dive-801.
      expect(
        plan.filesToWrite.keys.any((k) => k.contains('Dive-801')),
        isFalse,
      );
      expect(plan.stats.newDives, 0);
      expect(plan.stats.updatedDives, 1);
    });

    test('a remote Divesoft dive (decimal Serial) is matched by a local dive '
        'stored with either serial reading', () {
      final files = <String, String?>{
        '2026/04/19-Sun-15=18=45/Dive-705': 'duration 57:30 min\n'
            'rating 2\n'
            'divemaster ""\n'
            'buddy ""\n'
            'suit ""\n',
        '2026/04/19-Sun-15=18=45/Divecomputer':
            'model "Divesoft Liberty"\nkeyvalue "Serial" "1234567"\n',
      };
      final snap = RemoteSnapshot.fromFiles(files);
      for (final serial in [1234567, 0x1234567]) {
        final plan = SyncPlanner().plan(
          ccrlogDives: [
            _bundle(
              diveId: _diveIdA,
              gasMixes: const [],
              annotation: _testAnnotation(rating: 5),
              dcSerial: serial,
            ),
          ],
          existingDivesBySerialAndStart: snap.existingDivesBySerialAndStart,
          existingMaxDiveNumber: snap.existingMaxDiveNumber,
          existingTopLevel: const [],
          existingSites: const {},
        );
        expect(plan.stats.newDives, 0, reason: 'serial $serial');
        expect(
          plan.filesToWrite.keys.where((k) => k.endsWith('/Divecomputer')),
          isEmpty,
          reason: 'serial $serial',
        );
        expect(plan.filesToWrite.keys.where((k) => k.contains('Dive-705')),
            hasLength(1));
      }
    });

    test('existing dive with empty (unreadable) Dive-NNN aborts rather '
        'than silently overwriting', () {
      final planner = SyncPlanner();
      final bundle = _bundle(diveId: _diveIdA);
      final existing = ExistingRemoteDive(
        folderSegments: ['2026', '04', '04-Sat-13=18=45'],
        diveNumber: 705,
        serial: 0xb89641e4,
        startTime: 1776611925,
        // Empty mimics a parse failure at scan time on a corrupt Dive-NNN.
        diveLines: const [],
      );
      final plan = planner.plan(
        ccrlogDives: [bundle],
        existingDivesBySerialAndStart: {
          (serial: 0xb89641e4, startTime: 1776611925): existing,
        },
        existingMaxDiveNumber: 705,
        existingTopLevel: const [],
        existingSites: const {},
      );

      // Nothing written for this dive.
      expect(
        plan.filesToWrite.keys
            .where((k) => k.contains('04-Sat-13=18=45'))
            .toList(),
        isEmpty,
      );
      expect(plan.abortedDives, hasLength(1));
      expect(
        plan.abortedDives.first.reason,
        AbortReason.foreignEditConflict,
      );
      expect(
        plan.abortedDives.first.conflictingLines,
        contains('<unreadable Dive-NNN>'),
      );
    });

    test('existing site at same coords: reuse Subsurface UUID, do not '
        'create orphan under CCRLog hash', () {
      // Regression for the 2026-05-11 smoke: Subsurface assigns random
      // UUIDs at site creation; CCRLog computes SHA-256(lat,lon). On
      // first push, every site was being duplicated under CCRLog's
      // hash and every dive's divesiteid was being rewritten. Fix:
      // when CCRLog's mapped site shares coords with an existing Site
      // file, reuse the existing Subsurface UUID.
      final planner = SyncPlanner();
      final ann = _annotation(
        diveId: _diveIdA,
        siteName: 'Om Sid - Dahab',
        siteLatitude: 28.420550,
        siteLongitude: 34.457473,
      );
      final bundle = _bundle(diveId: _diveIdA, annotation: ann);

      // Subsurface's pre-existing Site file under a random UUID.
      const subsurfaceHex = 'a36eace9';
      final existingSiteLines = parseSubsurfaceFile(
        'name "Om Sid - Dahab"\n'
        'description ""\n'
        'notes ""\n'
        'gps 28.420550 34.457473\n',
        kind: SubsurfaceFileKind.site,
      ).lines;

      final plan = planner.plan(
        ccrlogDives: [bundle],
        existingDivesBySerialAndStart: const {},
        existingMaxDiveNumber: 0,
        existingTopLevel: const [],
        existingSites: {subsurfaceHex: existingSiteLines},
      );

      // The new dive points at the EXISTING Subsurface UUID.
      expect(
        plan.filesToWrite['2026/04/19-Sun-15=18=45/Dive-705'],
        contains('divesiteid $subsurfaceHex\n'),
      );
      // No orphan under CCRLog's SHA-256 hash was created, and the
      // existing Site file already holds what CCRLog would write.
      final siteWrites = plan.filesToWrite.keys
          .where((k) => k.startsWith('01-Divesites/'))
          .toList();
      expect(siteWrites, isEmpty,
          reason: 'CCRLog must not create duplicate Site files for sites '
              'Subsurface already has under its own UUID.');
    });

    group('a new dive at GPS that two existing sites share', () {
      const shoreHex = _shoreHex;
      const platformHex = _platformHex;
      final existingSites = _sharedGpsSites();
      SyncPlan planNewDive(String siteName) => SyncPlanner().plan(
            ccrlogDives: [
              _bundle(
                diveId: _diveIdA,
                annotation: _annotation(
                  diveId: _diveIdA,
                  siteName: siteName,
                  siteLatitude: 52.12345,
                  siteLongitude: 4.56789,
                ),
              ),
            ],
            existingDivesBySerialAndStart: const {},
            existingMaxDiveNumber: 0,
            existingTopLevel: const [],
            existingSites: existingSites,
          );
      const divePath = '2026/04/19-Sun-15=18=45/Dive-705';

      test('points at the site with its name and renames neither', () {
        for (final (name, hex) in [
          ('Quarry North - Shore entry', shoreHex),
          ('Quarry North - Platform', platformHex),
        ]) {
          final plan = planNewDive(name);
          expect(plan.filesToWrite[divePath], contains('divesiteid $hex\n'),
              reason: name);
          expect(
            plan.filesToWrite.keys.where((k) => k.startsWith('01-Divesites/')),
            isEmpty,
            reason: name,
          );
        }
      });

      test('with a name neither site has, gets a site of its own', () {
        final plan = planNewDive('Quarry North - Night entry');

        final siteWrites = plan.filesToWrite.keys
            .where((k) => k.startsWith('01-Divesites/'))
            .toList();
        expect(siteWrites, hasLength(1));
        final hex = siteWrites.single.substring('01-Divesites/Site-'.length);
        expect(hex, isNot(anyOf(shoreHex, platformHex)));
        expect(plan.filesToWrite[siteWrites.single],
            contains('name "Quarry North - Night entry"\n'));
        expect(plan.filesToWrite[divePath], contains('divesiteid $hex\n'));
      });
    });

    // The merge never rewrites an existing dive's `divesiteid`, so its
    // site goes into the Site file it points to only when that is still
    // the same place.
    group('an existing dive pointing at one of two same-GPS sites', () {
      SyncPlan planExisting(
        String siteName, {
        double lat = 52.12345,
        double lon = 4.56789,
      }) =>
          _planAgainst(
            'duration 57:30 min\n'
            'divesiteid $_shoreHex\n',
            _annotation(
              diveId: _diveIdA,
              siteName: siteName,
              siteLatitude: lat,
              siteLongitude: lon,
            ),
            existingSites: _sharedGpsSites(),
          );
      Iterable<String> siteWrites(SyncPlan plan) =>
          plan.filesToWrite.keys.where((k) => k.startsWith('01-Divesites/'));

      test('renamed in CCRLog: renames the site it points to', () {
        final plan = planExisting('Quarry North - Shore entry (east)');

        expect(siteWrites(plan), ['01-Divesites/Site-$_shoreHex']);
        expect(plan.filesToWrite['01-Divesites/Site-$_shoreHex'],
            contains('name "Quarry North - Shore entry (east)"\n'));
      });

      test('given the other site\'s name in CCRLog: renames neither', () {
        final plan = planExisting('Quarry North - Platform');

        expect(siteWrites(plan), isEmpty);
      });

      test('moved elsewhere in CCRLog: leaves the site it points to', () {
        final plan = planExisting('Quarry South', lat: 52.2, lon: 4.6);

        final writes = siteWrites(plan).toList();
        expect(writes, hasLength(1));
        expect(writes.single,
            isNot(anyOf('01-Divesites/Site-$_shoreHex',
                '01-Divesites/Site-$_platformHex')));
      });
    });

    test('site dedup: two CCRLog dives at same lat/lon → one Site-XXXX',
        () {
      final planner = SyncPlanner();
      final ann = _annotation(
        diveId: _diveIdA,
        siteName: 'Om Sid - Dahab',
        siteLatitude: 28.420550,
        siteLongitude: 34.457473,
      );
      final bundleA = _bundle(diveId: _diveIdA, annotation: ann);
      final bundleB = _bundle(
        diveId: _diveIdB,
        startTime: 1776611925 + 7200,
        annotation: ann.copyWith(diveId: _diveIdB),
      );

      final plan = planner.plan(
        ccrlogDives: [bundleA, bundleB],
        existingDivesBySerialAndStart: const {},
        existingMaxDiveNumber: 0,
        existingTopLevel: const [],
        existingSites: const {},
      );

      final siteFiles =
          plan.filesToWrite.keys.where((k) => k.startsWith('01-Divesites/'));
      expect(siteFiles.length, 1);
    });

    test('site preserve: existing description + notes are kept after '
        'planner overlays our name + gps', () {
      final planner = SyncPlanner();
      final ann = _annotation(
        diveId: _diveIdA,
        siteName: 'Om Sid - Dahab',
        siteLatitude: 28.420550,
        siteLongitude: 34.457473,
      );
      final bundle = _bundle(diveId: _diveIdA, annotation: ann);

      // Build the existing site as a parsed file that has user-typed
      // description, notes, and a geo line.
      const existingSiteText = 'name "OLD NAME"\n'
          'description "Awesome wreck"\n'
          'notes "Dive briefing in the cantina before."\n'
          'gps 1.0 2.0\n'
          'geo cat 2 origin 2 "Egypte"\n';
      final existingLines = parseSubsurfaceFile(
        existingSiteText,
        kind: SubsurfaceFileKind.site,
      ).lines;
      // Compute the hex id the mapper assigns to these coords by
      // scanning the planner output (don't duplicate the hashing logic
      // here — the mapper's id is what we want to merge against).
      final preliminary = planner.plan(
        ccrlogDives: [bundle],
        existingDivesBySerialAndStart: const {},
        existingMaxDiveNumber: 0,
        existingTopLevel: const [],
        existingSites: const {},
      );
      final newSiteKey = preliminary.filesToWrite.keys
          .firstWhere((k) => k.startsWith('01-Divesites/'));
      final hexId = newSiteKey.split('/').last.substring('Site-'.length);

      final plan = planner.plan(
        ccrlogDives: [bundle],
        existingDivesBySerialAndStart: const {},
        existingMaxDiveNumber: 0,
        existingTopLevel: const [],
        existingSites: {hexId: existingLines},
      );

      final mergedText = plan.filesToWrite['01-Divesites/Site-$hexId']!;
      // User-typed description and notes survived.
      expect(mergedText, contains('description "Awesome wreck"'));
      expect(
        mergedText,
        contains('notes "Dive briefing in the cantina before."'),
      );
      // Geo line preserved verbatim.
      expect(mergedText, contains('geo cat 2 origin 2 "Egypte"'));
      // Our name overrode the old one.
      expect(mergedText, contains('name "Om Sid - Dahab"'));
      expect(mergedText, isNot(contains('OLD NAME')));
      // Our GPS replaced the placeholder.
      expect(mergedText, contains('gps 28.420550 34.457473'));
      expect(mergedText, isNot(contains('gps 1.0 2.0')));
    });

    test('00-Subsurface dedup on serial: existing divecomputerid for '
        'serial X is not duplicated', () {
      final planner = SyncPlanner();
      final dc = _diveComputer(serial: 0xb89641e4);
      final bundle = _bundle(
        diveId: _diveIdA,
        userDiveComputers: [dc],
      );

      // Existing top-level already has a divecomputerid for the same
      // serial (with a libdc-style deviceid that differs from ours).
      const existingTopText = 'version 3\n'
          'divecomputerid "Shearwater Petrel 3" deviceid=18545bf0 '
          'serial="b89641e4" nickname="Petrel 3"\n'
          'units PERSONALIZE METERS LITER BAR CELSIUS KG MINUTES\n';
      final existingTop =
          parseSubsurfaceFile(existingTopText, kind: SubsurfaceFileKind.top)
              .lines;

      final plan = planner.plan(
        ccrlogDives: [bundle],
        existingDivesBySerialAndStart: const {},
        existingMaxDiveNumber: 0,
        existingTopLevel: existingTop,
        existingSites: const {},
      );

      final topText = plan.filesToWrite['00-Subsurface']!;
      // Exactly one divecomputerid line for this serial.
      final dcIdLines = topText
          .split('\n')
          .where((l) => l.startsWith('divecomputerid '))
          .toList();
      expect(dcIdLines.length, 1);
      // The libdc deviceid (the one that was already there) wins —
      // our deviceid was not appended as a second line.
      expect(dcIdLines.single, contains('deviceid=18545bf0'));
    });

    test('00-Subsurface fingerprint append: 3 existing + 2 new → 5 total',
        () {
      final planner = SyncPlanner();
      final bundleA = _bundle(diveId: _diveIdA);
      final bundleB = _bundle(
        diveId: _diveIdB,
        startTime: 1776611925 + 3600,
      );

      const existingTopText = 'version 3\n'
          'fingerprint model=00000000 serial=00000000 deviceid=00000000 '
          'diveid=00000000 data=""\n'
          'fingerprint model=41ef6c17 serial=4383b51e deviceid=2939b109 '
          'diveid=e8b939e3 data="634587a2"\n'
          'fingerprint model=41ef6c17 serial=5677bfef deviceid=bbd14b39 '
          'diveid=ea446535 data="634a6c31"\n'
          'units PERSONALIZE METERS LITER BAR CELSIUS KG MINUTES\n';
      final existingTop =
          parseSubsurfaceFile(existingTopText, kind: SubsurfaceFileKind.top)
              .lines;

      final plan = planner.plan(
        ccrlogDives: [bundleA, bundleB],
        existingDivesBySerialAndStart: const {},
        existingMaxDiveNumber: 0,
        existingTopLevel: existingTop,
        existingSites: const {},
      );

      final topText = plan.filesToWrite['00-Subsurface']!;
      final fpLines = topText
          .split('\n')
          .where((l) => l.startsWith('fingerprint '))
          .toList();
      expect(fpLines.length, 5);
    });

    test('empty CCRLog state → no writes', () {
      final planner = SyncPlanner();
      final plan = planner.plan(
        ccrlogDives: const [],
        existingDivesBySerialAndStart: const {},
        existingMaxDiveNumber: 0,
        existingTopLevel: const [],
        existingSites: const {},
      );
      expect(plan.filesToWrite, isEmpty);
      expect(plan.diveIdsPlanned, isEmpty);
      expect(plan.stats.newDives, 0);
      expect(plan.stats.updatedDives, 0);
    });

    test('all dives already match remote unchanged → no writes', () {
      // Two CCRLog dives, both matched by remote (serial, startTime)
      // entries. The planner still maps and writes them — but if the
      // mapped output happens to byte-equal what's already on disk,
      // the orchestrator's commit step will no-op.
      //
      // This test asserts the *planner-level* invariant when there is
      // genuinely nothing for it to plan: an empty CCRLog state. The
      // "outputs unchanged" case is covered by the orchestrator's
      // second-syncNow-is-a-no-op test.
      final planner = SyncPlanner();
      final plan = planner.plan(
        ccrlogDives: const [],
        existingDivesBySerialAndStart: const {},
        existingMaxDiveNumber: 100,
        existingTopLevel: const [],
        existingSites: const {},
      );
      expect(plan.diveIdsPlanned, isEmpty);
      expect(plan.filesToWrite, isEmpty);
    });

    test('multiple new dives: first claims dcDiveNumber, second falls back', () {
      final planner = SyncPlanner();
      // Both fixture bundles share dcDiveNumber=705; the first new dive
      // claims 705, the second collides and increments to 706.
      final bundleA = _bundle(diveId: _diveIdA);
      final bundleB = _bundle(
        diveId: _diveIdB,
        startTime: 1776611925 + 3600,
      );
      final plan = planner.plan(
        ccrlogDives: [bundleA, bundleB],
        existingDivesBySerialAndStart: const {},
        existingMaxDiveNumber: 50,
        existingTopLevel: const [],
        existingSites: const {},
      );
      final diveFileNames = plan.filesToWrite.keys
          .where((k) => k.contains('Dive-'))
          .map((k) => k.split('/').last)
          .toList()
        ..sort();
      expect(diveFileNames, containsAll(['Dive-705', 'Dive-706']));
    });

    test(
        'new dive prefers dcDiveNumber even when existingMaxDiveNumber is '
        'much higher (regression: orphan Dive-1153 produced Dive-1154)', () {
      final planner = SyncPlanner();
      final bundle = _bundle(diveId: _diveIdA);
      final plan = planner.plan(
        ccrlogDives: [bundle],
        existingDivesBySerialAndStart: const {},
        // Simulate the user's bug scenario: an orphan Dive-1153 in the
        // remote (no corresponding live dive entry) pushed
        // existingMaxDiveNumber way past the live count.
        existingMaxDiveNumber: 1153,
        existingTopLevel: const [],
        existingSites: const {},
      );
      // dcDiveNumber=705 isn't a key in the remote → use it.
      expect(
        plan.filesToWrite.keys,
        contains('2026/04/19-Sun-15=18=45/Dive-705'),
      );
      expect(
        plan.filesToWrite.keys.any((k) => k.endsWith('Dive-1154')),
        isFalse,
      );
    });

    test(
        'orphan Dive-NNN past the real max does not push collision-walk '
        'beyond the real sequence (regression: orphan 1145 produced 1146 '
        'when real max was 712)', () {
      final planner = SyncPlanner();
      // Bundle's dcDiveNumber is 705 (per _bundle default). We populate
      // existingDivesBySerialAndStart with parseable dives 700..712 that
      // include 705 — so dcDiveNumber=705 collides and the planner falls
      // into the walk-forward branch. Before the fix, that branch started
      // from existingMaxDiveNumber=1145 (the orphan), allocating Dive-1146.
      // After the fix it starts from max(remoteDiveNumbers)=712 and
      // allocates Dive-713.
      final existingDivesByKey =
          <({int serial, int startTime}), ExistingRemoteDive>{};
      for (var n = 700; n <= 712; n++) {
        existingDivesByKey[(serial: 0xCAFE0000 + n, startTime: 1700000000 + n)] =
            ExistingRemoteDive(
          folderSegments: ['2024', '01', '01-Mon-00=00=00'],
          diveNumber: n,
          serial: 0xCAFE0000 + n,
          startTime: 1700000000 + n,
          diveLines: parseSubsurfaceFile(
            'duration 30:00 min\n',
            kind: SubsurfaceFileKind.dive,
          ).lines,
        );
      }
      final bundle = _bundle(diveId: _diveIdA);
      final plan = planner.plan(
        ccrlogDives: [bundle],
        existingDivesBySerialAndStart: existingDivesByKey,
        // Orphan Dive-1145 file with no parseable Divecomputer pushes the
        // overall max up; it does NOT appear in existingDivesBySerialAndStart.
        existingMaxDiveNumber: 1145,
        existingTopLevel: const [],
        existingSites: const {},
      );
      final newDiveFile = plan.filesToWrite.keys
          .firstWhere((k) => k.contains('19-Sun-15=18=45/Dive-'));
      expect(newDiveFile.endsWith('/Dive-713'), isTrue,
          reason: 'expected next-after-real-max (712 → 713), '
              'got $newDiveFile');
      expect(
        plan.filesToWrite.keys.any((k) => k.endsWith('Dive-1146')),
        isFalse,
      );
    });

    test(
        'remote has parseable dives → walk forward instead of trusting '
        'a wildly out-of-range dcDiveNumber (regression: Petrel reset '
        'made Dive-1146 sit next to Dive-713)', () {
      final planner = SyncPlanner();
      // Subsurface already has dives 700..712 logged.
      final existing = <({int serial, int startTime}), ExistingRemoteDive>{};
      for (var n = 700; n <= 712; n++) {
        existing[(serial: 0xCAFE0000 + n, startTime: 1700000000 + n)] =
            ExistingRemoteDive(
          folderSegments: ['2026', '04', '$n-Mon-00=00=00'],
          diveNumber: n,
          serial: 0xCAFE0000 + n,
          startTime: 1700000000 + n,
          diveLines: parseSubsurfaceFile(
            'duration 30:00 min\n',
            kind: SubsurfaceFileKind.dive,
          ).lines,
        );
      }
      // The new dive's Petrel reports dcDiveNumber=1146 (far ahead of
      // anything in Subsurface — perhaps the unit was reset, used by a
      // previous owner, or counts power-on sessions).
      final bundle = _bundle(diveId: _diveIdA);
      final bumped = SubsurfaceDiveInput(
        id: bundle.dive.id,
        dcSerial: bundle.dive.dcSerial,
        dcVendor: bundle.dive.dcVendor,
        dcProduct: bundle.dive.dcProduct,
        dcFamily: bundle.dive.dcFamily,
        dcDiveNumber: 1146,
        startTime: bundle.dive.startTime,
        durationSeconds: bundle.dive.durationSeconds,
        maxDepthMm: bundle.dive.maxDepthMm,
        diveMode: bundle.dive.diveMode,
        gfLow: bundle.dive.gfLow,
        gfHigh: bundle.dive.gfHigh,
        atmosphericPressureMbar: bundle.dive.atmosphericPressureMbar,
        waterDensity: bundle.dive.waterDensity,
        logVersion: bundle.dive.logVersion,
        dcModel: bundle.dive.dcModel,
        dcFirmware: bundle.dive.dcFirmware,
        configuredStackSeconds: bundle.dive.configuredStackSeconds,
        stackRemainingAtStartSeconds: bundle.dive.stackRemainingAtStartSeconds,
        stackRemainingAtEndSeconds: bundle.dive.stackRemainingAtEndSeconds,
      );
      final patched = CcrlogDiveBundle(
        dive: bumped,
        samples: bundle.samples,
        annotation: bundle.annotation,
        gasMixes: bundle.gasMixes,
        tanks: bundle.tanks,
        cylindersByMixIndex: bundle.cylindersByMixIndex,
        userDiveComputers: bundle.userDiveComputers,
      );

      final plan = planner.plan(
        ccrlogDives: [patched],
        existingDivesBySerialAndStart: existing,
        existingMaxDiveNumber: 712,
        existingTopLevel: const [],
        existingSites: const {},
      );

      expect(
        plan.filesToWrite.keys.any((k) => k.endsWith('/Dive-713')),
        isTrue,
        reason: 'expected Dive-713 (next after the real max), '
            'got ${plan.filesToWrite.keys.toList()}',
      );
      expect(
        plan.filesToWrite.keys.any((k) => k.endsWith('/Dive-1146')),
        isFalse,
        reason: 'must not honour dcDiveNumber=1146 when Subsurface '
            "already has 13 dives — that creates the user's reported gap",
      );
    });

    test(
        'bundles are assigned numbers in chronological order regardless of '
        "input order (regression: caller's DESC-by-start_time list "
        'produced inverted Dive-1146 May-25 vs Dive-1147 May-24)', () {
      final planner = SyncPlanner();
      // Subsurface has one existing dive so we hit the walk-forward path.
      final existing = <({int serial, int startTime}), ExistingRemoteDive>{
        (serial: 0xCAFE0001, startTime: 1700000001):
            ExistingRemoteDive(
          folderSegments: ['2026', '04', '01-Mon-00=00=00'],
          diveNumber: 712,
          serial: 0xCAFE0001,
          startTime: 1700000001,
          diveLines: parseSubsurfaceFile(
            'duration 30:00 min\n',
            kind: SubsurfaceFileKind.dive,
          ).lines,
        ),
      };
      // Two new dives, 24 hours apart. The OLDER one is passed second,
      // mirroring DiveDao.getAllDives()'s ORDER BY start_time DESC.
      const earlierStart = 1700000100;
      const laterStart = earlierStart + 86400;
      final newer = _bundle(diveId: _diveIdA, startTime: laterStart);
      final older = _bundle(diveId: _diveIdB, startTime: earlierStart);

      final plan = planner.plan(
        ccrlogDives: [newer, older], // intentionally newest-first
        existingDivesBySerialAndStart: existing,
        existingMaxDiveNumber: 712,
        existingTopLevel: const [],
        existingSites: const {},
      );

      // Pull out the two new Dive-NNN files. The path prefix is the
      // UTC-derived folder, which sorts chronologically, so sorting
      // paths puts the earlier dive first.
      final divePaths = plan.filesToWrite.keys
          .where((k) =>
              k.contains('/Dive-') && !k.endsWith('Divecomputer'))
          .toList()
        ..sort();
      expect(divePaths, hasLength(2));
      int diveNumberOf(String path) =>
          int.parse(path.split('/').last.split('-').last);
      final olderNumber = diveNumberOf(divePaths.first);
      final newerNumber = diveNumberOf(divePaths.last);
      expect(olderNumber, 713,
          reason: 'older dive should get the next-after-max number');
      expect(newerNumber, 714,
          reason: 'newer dive should get the one after the older dive');
      expect(olderNumber, lessThan(newerNumber),
          reason: 'chronological ordering must be preserved regardless '
              'of bundle input order');
    });

    test('SyncPlan exposes empty abortedDives by default', () {
      final planner = SyncPlanner();
      final plan = planner.plan(
        ccrlogDives: const [],
        existingDivesBySerialAndStart: const {},
        existingMaxDiveNumber: 0,
        existingTopLevel: const [],
        existingSites: const {},
      );
      expect(plan.abortedDives, isEmpty);
      expect(plan.stats.abortedDives, 0);
    });
  });

  group('_mergeDiveLines (via plan() existing-dive branch)', () {
    test('happy path: only owned fields change, non-owned lines preserved',
        () {
      final existingText = 'duration 57:30 min\n'
          'rating 3\n'
          'divemaster ""\n'
          'buddy "Alice"\n'
          'suit ""\n'
          'cylinder vol=3.0l workpressure=232.0bar description="3ℓ" o2=21%\n';
      final existing = parseSubsurfaceFile(
        existingText,
        kind: SubsurfaceFileKind.dive,
      ).lines;

      final planner = SyncPlanner();
      // gasMixes: const [] so the mapper emits no cylinder lines, matching
      // the existing fixture (which has a single cylinder we preserve verbatim).
      final bundle = _bundle(
        diveId: _diveIdA,
        annotation: _testAnnotation(rating: 5, notes: 'great viz'),
        gasMixes: const [],
      );
      final plan = planner.plan(
        ccrlogDives: [bundle],
        existingDivesBySerialAndStart: {
          (serial: bundle.dive.dcSerial, startTime: bundle.dive.startTime):
              ExistingRemoteDive(
            folderSegments: ['2026', '04', '19-Sun-15=18=45'],
            diveNumber: 42,
            serial: bundle.dive.dcSerial,
            startTime: bundle.dive.startTime,
            diveLines: existing,
          ),
        },
        existingMaxDiveNumber: 42,
        existingTopLevel: const [],
        existingSites: const {},
      );

      // No Divecomputer file in the plan — Phase 1 never touches it for
      // existing dives.
      expect(
        plan.filesToWrite.keys
            .where((k) => k.endsWith('/Divecomputer'))
            .toList(),
        isEmpty,
      );
      // The Dive-NNN file IS in the plan.
      const divePath = '2026/04/19-Sun-15=18=45/Dive-42';
      expect(plan.filesToWrite.containsKey(divePath), isTrue);
      final out = plan.filesToWrite[divePath]!;
      // Owned lines changed:
      expect(out, contains('rating 5'));
      expect(out, contains('notes "great viz"'));
      // Non-owned line preserved verbatim:
      expect(out,
          contains('cylinder vol=3.0l workpressure=232.0bar description="3ℓ" o2=21%'));
      expect(plan.stats.updatedDives, 1);
      expect(plan.abortedDives, isEmpty);
    });

    test('foreign edit on a non-owned line is preserved verbatim, not '
        'overwritten', () {
      // Subsurface side has a user-edited cylinder. CCRLog has different
      // gasMixes for the same dive (the 2026-05-08 incident shape). The
      // merge must NOT overwrite Subsurface's cylinder.
      final existingText = 'duration 57:30 min\n'
          'rating 3\n'
          'divemaster ""\n'
          'buddy ""\n'
          'suit ""\n'
          'cylinder vol=11.1l workpressure=232.0bar description="user-edited" o2=32%\n';
      final existing = parseSubsurfaceFile(
        existingText,
        kind: SubsurfaceFileKind.dive,
      ).lines;
      final planner = SyncPlanner();
      final bundle = _bundle(
        diveId: _diveIdA,
        annotation: _testAnnotation(rating: 5),
      );
      final plan = planner.plan(
        ccrlogDives: [bundle],
        existingDivesBySerialAndStart: {
          (serial: bundle.dive.dcSerial, startTime: bundle.dive.startTime):
              ExistingRemoteDive(
            folderSegments: ['2026', '04', '19-Sun-15=18=45'],
            diveNumber: 42,
            serial: bundle.dive.dcSerial,
            startTime: bundle.dive.startTime,
            diveLines: existing,
          ),
        },
        existingMaxDiveNumber: 42,
        existingTopLevel: const [],
        existingSites: const {},
      );
      expect(plan.abortedDives, isEmpty);
      const divePath = '2026/04/19-Sun-15=18=45/Dive-42';
      final out = plan.filesToWrite[divePath]!;
      // Owned rating change went through:
      expect(out, contains('rating 5'));
      // CRITICAL: user's cylinder edit is preserved byte-for-byte. The
      // mapper would have emitted three different cylinder lines from
      // _threeGasMixes(), but the merge dropped them and kept Subsurface's.
      expect(out, contains(
          'cylinder vol=11.1l workpressure=232.0bar description="user-edited" o2=32%'));
      expect(out, isNot(contains('vol=3.0l')));
    });

    test(
        'idempotent: re-plan on already-matching state writes nothing for '
        'existing dives', () {
      final bundle = _bundle(
        diveId: _diveIdA,
        annotation: _testAnnotation(rating: 3, notes: 'x'),
      );
      final mapper = CcrlogToSubsurfaceMapper();
      final mapped = mapper.mapDive(
        dive: bundle.dive,
        samples: bundle.samples,
        annotation: bundle.annotation,
        gasMixes: bundle.gasMixes,
        tanks: bundle.tanks,
        cylindersByMixIndex: bundle.cylindersByMixIndex,
        nextSubsurfaceDiveNumber: 42,
      );
      final planner = SyncPlanner();
      final plan = planner.plan(
        ccrlogDives: [bundle],
        existingDivesBySerialAndStart: {
          (serial: bundle.dive.dcSerial, startTime: bundle.dive.startTime):
              ExistingRemoteDive(
            folderSegments: ['2026', '04', '19-Sun-15=18=45'],
            diveNumber: 42,
            serial: bundle.dive.dcSerial,
            startTime: bundle.dive.startTime,
            diveLines: mapped.diveLines,
          ),
        },
        existingMaxDiveNumber: 42,
        existingTopLevel: const [],
        existingSites: const {},
      );
      expect(plan.filesToWrite, isEmpty);
      expect(plan.stats.skippedDives, 1);
      expect(plan.stats.updatedDives, 0);
      expect(plan.abortedDives, isEmpty);
    });

    test(
        'incident replica: user-edited cylinder is preserved, never '
        'overwritten by CCRLog', () {
      final divText = File('test/fixtures/subsurface_incident_replica/Dive-697')
          .readAsStringSync();
      final existingLines =
          parseSubsurfaceFile(divText, kind: SubsurfaceFileKind.dive).lines;
      final planner = SyncPlanner();
      // Default bundle uses _threeGasMixes() — three cylinder lines, none
      // matching the fixture's single user-manually-tuned cylinder. The
      // merge must KEEP the user's cylinder and not let CCRLog's overwrite
      // it. (The 2026-05-08 incident was the OPPOSITE: full overwrite of
      // the on-disk Dive-NNN with CCRLog's emission.)
      final bundle = _bundle(diveId: _diveIdA);
      final plan = planner.plan(
        ccrlogDives: [bundle],
        existingDivesBySerialAndStart: {
          (serial: bundle.dive.dcSerial, startTime: bundle.dive.startTime):
              ExistingRemoteDive(
            folderSegments: ['2026', '02', '08-Sun-09=43=19'],
            diveNumber: 697,
            serial: bundle.dive.dcSerial,
            startTime: bundle.dive.startTime,
            diveLines: existingLines,
          ),
        },
        existingMaxDiveNumber: 697,
        existingTopLevel: const [],
        existingSites: const {},
      );

      // Divecomputer is NEVER staged for an existing dive — sample stream
      // is sacred.
      expect(
        plan.filesToWrite.keys
            .where((k) => k.contains('Divecomputer'))
            .toList(),
        isEmpty,
      );
      expect(plan.abortedDives, isEmpty);
      // The user's cylinder line survives byte-for-byte.
      final divePath = plan.filesToWrite.keys
          .firstWhere((k) => k.contains('Dive-697'));
      final out = plan.filesToWrite[divePath]!;
      expect(
        out,
        contains(
          'cylinder vol=3.0l workpressure=232.0bar description="user-manually-tuned" o2=18.0% he=23.0% use="diluent" depth=6.249m',
        ),
        reason: 'If this fails, the 2026-05-08 data-loss class of bug is back.',
      );
      // CCRLog's three default cylinders were NOT injected.
      expect(out, isNot(contains('"3L tank"')));
    });

    // Older Subsurface files often lack the divemaster / buddy / suit
    // lines the mapper always emits. On the real repository the merge
    // appended `divemaster ""` to 523 dives and `suit ""` to 436.
    test('empty owned lines the file lacks are not appended', () {
      final plan = _planAgainst(
        'duration 57:30 min\n'
        'rating 3\n',
        DiveAnnotation(
          diveId: _diveIdA,
          rating: 3,
          createdAt: DateTime.utc(2026, 5, 1),
          updatedAt: DateTime.utc(2026, 5, 1),
        ),
      );
      expect(plan.filesToWrite, isEmpty);
      expect(plan.stats.skippedDives, 1);
    });

    test('an owned line that reads the same is not rewritten for '
        'formatting', () {
      final plan = _planAgainst(
        'duration 57:30 min\n'
        'rating 7\n'
        'buddy "Adri , Bjorn Hack"\n'
        'airtemp 25°C\n'
        'weightsystem weight=2.376kg description="p-weight"\n'
        'weightsystem weight=0.0kg\n',
        DiveAnnotation(
          diveId: _diveIdA,
          // The read mapper clamps ratings to 1..5.
          rating: 5,
          buddies: const ['Adri', 'Bjorn Hack'],
          airTempC: 25,
          weights: const [
            Weight(weightKg: 2.376, description: 'p-weight'),
            Weight(weightKg: 0, description: ''),
          ],
          createdAt: DateTime.utc(2026, 5, 1),
          updatedAt: DateTime.utc(2026, 5, 1),
        ),
      );
      expect(plan.filesToWrite, isEmpty);
      expect(plan.stats.skippedDives, 1);
    });

    test('a real owned edit made in CCRLog is still pushed', () {
      final plan = _planAgainst(
        'duration 57:30 min\n'
        'divemaster ""\n'
        'buddy "Adri , Bjorn Hack"\n'
        'suit "Wetsuit"\n'
        'weightsystem weight=2.376kg description="p-weight"\n'
        'weightsystem weight=1.0kg description="belt"\n',
        DiveAnnotation(
          diveId: _diveIdA,
          divemaster: 'Robin',
          buddies: const ['Adri', 'Kim'],
          // suit cleared in CCRLog
          chill: 4,
          weights: const [
            Weight(weightKg: 2.376, description: 'p-weight'),
            Weight(weightKg: 1.5, description: 'belt'),
          ],
          createdAt: DateTime.utc(2026, 5, 1),
          updatedAt: DateTime.utc(2026, 5, 1),
        ),
      );
      const divePath = '2026/04/19-Sun-15=18=45/Dive-42';
      expect(plan.stats.updatedDives, 1);
      expect(plan.diveIdsPlanned, [_diveIdA]);
      expect(plan.filesToWrite.keys.where((k) => k.contains('Divecomputer')),
          isEmpty);
      expect(
        plan.filesToWrite[divePath],
        'duration 57:30 min\n'
        'divemaster "Robin"\n'
        'buddy "Adri, Kim"\n'
        'suit ""\n'
        // The group is replaced as a whole, at gram precision.
        'weightsystem weight=2.376kg description="p-weight"\n'
        'weightsystem weight=1.5kg description="belt"\n'
        'chill 4\n',
      );
    });
  });

  // The writer only knows how to write Shearwater dives. A dive from
  // another brand (dc_family set, or a vendor that is set and isn't
  // Shearwater) is written only as the merge of CCRLog's own lines into a
  // dive Subsurface Cloud already has; one it doesn't have is left out.
  group('dives from other brands', () {
    test('another brand is a set dc_family, or a vendor that is set and '
        "isn't Shearwater", () {
      SubsurfaceDiveInput dive(String? vendor, int? family,
              [String? product]) =>
          _ccrPetrelDive(
              diveId: _diveIdA,
              dcVendor: vendor,
              dcProduct: product,
              dcFamily: family);
      expect(dive(null, null).isOtherBrand, isFalse);
      expect(dive('Shearwater', null, 'Petrel 3').isOtherBrand, isFalse);
      expect(dive('Divesoft', null, 'Liberty').isOtherBrand, isTrue);
      expect(dive(null, _libdcFamily).isOtherBrand, isTrue);
      expect(dive('Shearwater', _libdcFamily).isOtherBrand, isTrue);
      expect(dive('Garmin', -1).isOtherBrand, isTrue);
      // A Shearwater model line without the vendor (`model "Perdix 2"`)
      // splits as vendor 'Perdix', product '2'. As a copy it is Shearwater.
      expect(dive('Perdix', null, '2').isOtherBrand, isFalse);
      expect(dive('Peregrine', null, 'TX').isOtherBrand, isFalse);
      expect(dive('Perdix', null, 'Mk9').isOtherBrand, isTrue);
      expect(dive('Perdix', _libdcFamily, '2').isOtherBrand, isTrue);

      expect(const SubsurfaceDiveComputerInput(
              serial: 1, model: 3, dcVendor: null, dcFamily: null)
          .isOtherBrand, isFalse);
      expect(const SubsurfaceDiveComputerInput(
              serial: 1, model: 3, dcVendor: 'Shearwater', dcFamily: null)
          .isOtherBrand, isFalse);
      expect(const SubsurfaceDiveComputerInput(
              serial: 1, model: 0, dcVendor: 'Divesoft', dcFamily: null)
          .isOtherBrand, isTrue);
      expect(const SubsurfaceDiveComputerInput(
              serial: 1, model: 0, dcVendor: null, dcFamily: _libdcFamily)
          .isOtherBrand, isTrue);
    });

    test('the planner leaves out an other-brand dive that matches no remote '
        'dive, and counts it', () {
      for (final (vendor, family) in const [
        ('Divesoft', _libdcFamily),
        ('Garmin', -1),
      ]) {
        final plan = SyncPlanner().plan(
          ccrlogDives: [
            _bundle(
              diveId: _diveIdA,
              dcSerial: 1234567,
              dcVendor: vendor,
              dcFamily: family,
              annotation: _annotation(
                diveId: _diveIdA,
                siteName: 'Quarry North',
                siteLatitude: 52.12345,
                siteLongitude: 4.56789,
              ),
              userDiveComputers: [_diveComputer(serial: 0xb89641e4)],
            ),
          ],
          existingDivesBySerialAndStart: const {},
          existingMaxDiveNumber: 0,
          existingTopLevel: const [],
          existingSites: const {},
        );

        // Nothing at all: no Dive-NNN, Divecomputer, Site or 00-Subsurface.
        expect(plan.filesToWrite, isEmpty, reason: vendor);
        expect(plan.diveIdsPlanned, isEmpty, reason: vendor);
        expect(plan.stats.newDives, 0, reason: vendor);
        expect(plan.stats.updatedDives, 0, reason: vendor);
        expect(plan.stats.otherBrandDives, 1, reason: vendor);
      }
    });

    test('a refreshed other-brand copy that matches a remote dive gets its '
        'CCRLog-owned lines merged, and its Divecomputer file is '
        'byte-identical', () {
      final files = _divesoftRepo();
      // A download refresh stores the decimal serial and sets dc_family;
      // its samples are libdivecomputer's, not the ones Subsurface wrote.
      final bundle = _divesoftCopy(
        diveId: _diveIdA,
        dcSerial: 1234567,
        dcFamily: _libdcFamily,
      );

      final plan = _planOn(files, [bundle]);
      final after = {...files, ...plan.filesToWrite};

      expect(plan.filesToWrite.keys,
          isNot(contains('$_divesoftFolder/Divecomputer')));
      expect(after['$_divesoftFolder/Divecomputer'],
          files['$_divesoftFolder/Divecomputer']);

      final diveText = plan.filesToWrite['$_divesoftFolder/Dive-412']!;
      expect(diveText,
          contains('notes "Cells 1 and 2 swapped after the dive"'));
      expect(diveText, contains('buddy "Sam, Robin"'));
      expect(diveText, isNot(contains('Written in Subsurface')));
      // The lines CCRLog doesn't own stay as Subsurface wrote them.
      expect(diveText, startsWith('duration 48:20 min\nrating 3\n'
          'divesiteid $_divesoftSiteHex\n'));
      expect(diveText, contains('o2=100.0% use="oxygen"'));
      // The site it points to takes CCRLog's name.
      expect(plan.filesToWrite['01-Divesites/Site-$_divesoftSiteHex'],
          contains('name "Quarry North - Shore entry"'));
      // No Shearwater fingerprint or divecomputerid line for it.
      expect(after['00-Subsurface'], files['00-Subsurface']);

      expect(plan.stats.updatedDives, 1);
      expect(plan.stats.newDives, 0);
      expect(plan.stats.otherBrandDives, 0);
      expect(plan.diveIdsPlanned, [_diveIdA]);
    });

    test("an unrefreshed non-Shearwater copy (vendor 'Divesoft', dcFamily "
        'null) is treated by the same rule', () {
      final files = _divesoftRepo();
      // The bootstrap stores the legacy hex reading of the Serial text.
      final matched = _divesoftCopy(diveId: _diveIdA, dcSerial: 0x1234567);
      final unmatched = _divesoftCopy(
        diveId: _diveIdB,
        dcSerial: 0x1234567,
        startTime: _divesoftStart + 86400,
      );

      final plan = _planOn(files, [matched, unmatched]);
      final after = {...files, ...plan.filesToWrite};

      expect(after['$_divesoftFolder/Divecomputer'],
          files['$_divesoftFolder/Divecomputer']);
      expect(plan.filesToWrite['$_divesoftFolder/Dive-412'],
          contains('notes "Cells 1 and 2 swapped after the dive"'));
      expect(after['00-Subsurface'], files['00-Subsurface']);
      // Nothing for the dive Subsurface Cloud doesn't have.
      expect(
        plan.filesToWrite.keys.where((k) => k.startsWith('2025/06/15-')),
        isEmpty,
      );
      expect(plan.diveIdsPlanned, [_diveIdA]);
      expect(plan.stats.updatedDives, 1);
      expect(plan.stats.newDives, 0);
      expect(plan.stats.otherBrandDives, 1);
    });

    test('a Shearwater dive next to them is planned as before', () {
      final files = _divesoftRepo();
      final petrel = _bundle(
        diveId: _diveIdC,
        annotation: _testAnnotation(rating: 4, notes: 'Petrel dive'),
        userDiveComputers: [_diveComputer(serial: 0xb89641e4)],
      );

      final alone = _planOn(files, [petrel]);
      final mixed = _planOn(files, [
        // Earlier than the Petrel dive: if it were numbered, it would take
        // the Petrel dive's Dive-NNN.
        _divesoftCopy(
          diveId: _diveIdB,
          dcSerial: 1234567,
          dcFamily: _libdcFamily,
          startTime: _divesoftStart + 86400,
        ),
        petrel,
        _divesoftCopy(
          diveId: _diveIdA,
          dcSerial: 1234567,
          dcFamily: _libdcFamily,
        ),
      ]);

      expect(alone.filesToWrite.keys,
          contains('2026/04/19-Sun-15=18=45/Dive-413'));
      expect(alone.filesToWrite.keys, contains('00-Subsurface'));
      // Every file the Petrel dive writes is the same, byte for byte,
      // 00-Subsurface included.
      for (final entry in alone.filesToWrite.entries) {
        expect(mixed.filesToWrite[entry.key], entry.value, reason: entry.key);
      }
      // The only other writes are the matched copy's Dive-NNN and Site.
      expect(
        mixed.filesToWrite.keys
            .toSet()
            .difference(alone.filesToWrite.keys.toSet()),
        {
          '$_divesoftFolder/Dive-412',
          '01-Divesites/Site-$_divesoftSiteHex',
        },
      );
      expect(mixed.diveIdsPlanned, [_diveIdA, _diveIdC]);
      expect(mixed.stats.newDives, 1);
      expect(mixed.stats.updatedDives, 1);
      expect(mixed.stats.otherBrandDives, 1);
    });

    test("an unmatched copy with a vendor-less Shearwater model line "
        "('Perdix 2') is planned exactly as today, not left out", () {
      // `model "Perdix 2"` splits as vendor 'Perdix', product '2'. Before
      // brands were read, the planner ignored the vendor.
      SyncPlan planOf(CcrlogDiveBundle b) => SyncPlanner().plan(
            ccrlogDives: [b],
            existingDivesBySerialAndStart: const {},
            existingMaxDiveNumber: 0,
            existingTopLevel: const [],
            existingSites: const {},
          );
      final perdix = planOf(_bundle(
        diveId: _diveIdA,
        dcSerial: 0,
        dcVendor: 'Perdix',
        dcProduct: '2',
        userDiveComputers: [_diveComputer(serial: 0xb89641e4)],
      ));
      final asToday = planOf(_bundle(
        diveId: _diveIdA,
        dcSerial: 0,
        userDiveComputers: [_diveComputer(serial: 0xb89641e4)],
      ));

      expect(perdix.filesToWrite, isNotEmpty);
      expect(perdix.filesToWrite, asToday.filesToWrite);
      expect(perdix.diveIdsPlanned, [_diveIdA]);
      expect(perdix.stats.newDives, 1);
      expect(perdix.stats.otherBrandDives, 0);
    });

    test('an other-brand dive with dcSerial 0 is merged into a serial-less '
        'remote dive at the same start second, and left out at another', () {
      // A Divecomputer without a Serial is indexed under serial 0.
      final files = {
        ..._divesoftRepo(),
        '$_divesoftFolder/Divecomputer': 'model "Divesoft Liberty"\n'
            'dctype CCR\n'
            'maxdepth 32.4m\n'
            '  0:00 0.0m 14.0°C sensor1=0.71bar sensor2=0.7bar\n'
            '  0:10 3.1m sensor1=0.74bar sensor2=0.73bar\n',
      };

      final same = _planOn(files, [
        _divesoftCopy(diveId: _diveIdA, dcSerial: 0, dcFamily: _libdcFamily),
      ]);
      expect(same.filesToWrite['$_divesoftFolder/Dive-412'],
          contains('notes "Cells 1 and 2 swapped after the dive"'));
      expect(same.filesToWrite.keys,
          isNot(contains('$_divesoftFolder/Divecomputer')));
      expect(same.stats.updatedDives, 1);
      expect(same.stats.otherBrandDives, 0);

      final another = _planOn(files, [
        _divesoftCopy(
          diveId: _diveIdA,
          dcSerial: 0,
          dcFamily: _libdcFamily,
          startTime: _divesoftStart + 1,
        ),
      ]);
      expect(another.filesToWrite, isEmpty);
      expect(another.stats.otherBrandDives, 1);
    });

    test('a matched other-brand dive never runs the Divecomputer line '
        'builder', () {
      // Empty cell columns under a sample count of 4: the Divecomputer
      // line builder reads them and throws. The Dive-NNN lines don't.
      final broken = _twoCellSampleSet(diveId: _diveIdA).withoutCells();
      expect(
        () => CcrlogToSubsurfaceMapper().mapDive(
          dive: _ccrPetrelDive(diveId: _diveIdA),
          samples: broken,
          annotation: null,
          gasMixes: const [],
          tanks: const [],
          cylindersByMixIndex: const {},
          nextSubsurfaceDiveNumber: 1,
        ),
        throwsRangeError,
      );

      final plan = _planOn(_divesoftRepo(), [
        _divesoftCopy(
          diveId: _diveIdA,
          dcSerial: 1234567,
          dcFamily: _libdcFamily,
          samples: broken,
        ),
      ]);
      expect(plan.filesToWrite['$_divesoftFolder/Dive-412'],
          contains('notes "Cells 1 and 2 swapped after the dive"'));
      expect(plan.stats.updatedDives, 1);
    });

    test('a dive computer from another brand gets no divecomputerid line', () {
      final plan = SyncPlanner().plan(
        ccrlogDives: [
          _bundle(
            diveId: _diveIdA,
            userDiveComputers: [
              _diveComputer(serial: 0xb89641e4),
              const SubsurfaceDiveComputerInput(
                serial: 1234567,
                model: 0,
                dcVendor: 'Divesoft',
                dcFamily: _libdcFamily,
              ),
              const SubsurfaceDiveComputerInput(
                serial: 0x7654321,
                model: 13,
                dcVendor: 'Heinrichs Weikamp',
                dcFamily: null,
              ),
            ],
          ),
        ],
        existingDivesBySerialAndStart: const {},
        existingMaxDiveNumber: 0,
        existingTopLevel: const [],
        existingSites: const {},
      );

      final idLines = plan.filesToWrite['00-Subsurface']!
          .split('\n')
          .where((l) => l.startsWith('divecomputerid'))
          .toList();
      expect(idLines, hasLength(1));
      expect(idLines.single, contains('serial="b89641e4"'));
    });
  });
}

/// Plan [bundles] against the remote repository [files].
SyncPlan _planOn(Map<String, String> files, List<CcrlogDiveBundle> bundles) {
  final snap = RemoteSnapshot.fromFiles(files);
  return SyncPlanner().plan(
    ccrlogDives: bundles,
    existingDivesBySerialAndStart: snap.existingDivesBySerialAndStart,
    existingMaxDiveNumber: snap.existingMaxDiveNumber,
    existingTopLevel: snap.existingTopLevel,
    existingSites: snap.existingSites,
  );
}

// ── other-brand fixture ──────────────────────────────────────────────

/// Any set `dc_family`; the planner only reads whether one is set.
const _libdcFamily = 7;

/// A Divesoft Liberty dive on Subsurface Cloud, written out in the form
/// Subsurface's git writer gives one (there is no real Divesoft repository
/// among the fixtures yet). Its `Serial` is decimal text that also reads as
/// hex, and it has `SP change` events: the two things the planner's
/// Divecomputer rewrite for CCRLog-written files looks for.
const _divesoftFolder = '2025/06/14-Sat-10=12=30';
const _divesoftStart = 1749895950; // 2025-06-14T10:12:30Z
const _divesoftSiteHex = '5e1f0a77';

Map<String, String> _divesoftRepo() => {
      '00-Subsurface': 'version 3\n'
          'divecomputerid "Divesoft Liberty" deviceid=7a3c91e2 '
          'serial="1234567"\n'
          'fingerprint model=3b9f4a21 serial=0012d687 deviceid=7a3c91e2 '
          'diveid=4f2b8d10 data="5a1c33e0"\n',
      '01-Divesites/Site-$_divesoftSiteHex': 'name "Quarry North"\n'
          'description ""\n'
          'notes ""\n'
          'gps 52.123450 4.567890\n',
      '$_divesoftFolder/Dive-412': 'duration 48:20 min\n'
          'rating 3\n'
          'divesiteid $_divesoftSiteHex\n'
          'divemaster ""\n'
          'buddy "Sam"\n'
          'suit "Fourth Element Argonaut"\n'
          'notes "Written in Subsurface"\n'
          'cylinder vol=3.0l workpressure=200.0bar description="3ℓ 200 bar" '
          'o2=21.0% he=35.0% use="diluent"\n'
          'cylinder vol=3.0l workpressure=200.0bar description="3ℓ 200 bar" '
          'o2=100.0% use="oxygen"\n',
      '$_divesoftFolder/Divecomputer': 'model "Divesoft Liberty"\n'
          'deviceid 7a3c91e2\n'
          'diveid 4f2b8d10\n'
          'dctype CCR\n'
          'numberofoxygensensors 2\n'
          'maxdepth 32.4m\n'
          'meandepth 18.712m\n'
          'watertemp 9.0°C\n'
          'surfacepressure 1.012bar\n'
          'salinity 1030g/l\n'
          'keyvalue "Serial" "1234567"\n'
          'keyvalue "FW Version" "1.11.6"\n'
          'event 0:00 type=25 flags=6 name="gaschange" cylinder=0 '
          'o2=21.0% he=35.0%\n'
          'event 0:00 type=20 value=700 name="SP change"\n'
          'event 0:30 type=20 value=1300 name="SP change"\n'
          '  0:00 0.0m 14.0°C sensor1=0.71bar sensor2=0.7bar po2=0.7bar\n'
          '  0:10 3.1m sensor1=0.74bar sensor2=0.73bar\n'
          '  0:20 6.4m 13.0°C sensor1=0.78bar sensor2=0.77bar\n'
          '  0:30 9.8m sensor1=1.21bar sensor2=1.2bar po2=1.3bar\n'
          '  0:40 12.0m sensor1=1.29bar sensor2=1.3bar\n',
    };

/// CCRLog's copy of the [_divesoftRepo] dive with a new note, a second
/// buddy and a renamed site. Its samples are not the ones in the remote
/// Divecomputer file.
CcrlogDiveBundle _divesoftCopy({
  required String diveId,
  required int dcSerial,
  int? dcFamily,
  int startTime = _divesoftStart,
  SampleSet? samples,
}) {
  final now = DateTime.utc(2026, 11, 17);
  return _bundle(
    diveId: diveId,
    startTime: startTime,
    dcSerial: dcSerial,
    dcVendor: 'Divesoft',
    dcFamily: dcFamily,
    gasMixes: const [],
    samples: samples ?? _twoCellSampleSet(diveId: diveId),
    annotation: DiveAnnotation(
      diveId: diveId,
      notes: 'Cells 1 and 2 swapped after the dive',
      buddies: const ['Sam', 'Robin'],
      rating: 3,
      suit: 'Fourth Element Argonaut',
      siteName: 'Quarry North - Shore entry',
      siteLatitude: 52.12345,
      siteLongitude: 4.56789,
      createdAt: now,
      updatedAt: now,
    ),
    userDiveComputers: [
      _diveComputer(serial: 0xb89641e4),
      SubsurfaceDiveComputerInput(
        serial: dcSerial,
        model: 0,
        dcVendor: 'Divesoft',
        dcFamily: dcFamily,
      ),
    ],
  );
}

extension on SampleSet {
  /// This set with empty cell columns, shorter than [SampleSet.sampleCount].
  SampleSet withoutCells() => SampleSet(
        diveId: diveId,
        sampleCount: sampleCount,
        sampleIntervalMs: sampleIntervalMs,
        depthMeters: depthMeters,
        temperatureCelsius: temperatureCelsius,
        ppo2Bar: ppo2Bar,
        cellMv0: Float32List(0),
        cellMv1: Float32List(0),
        cellMv2: Float32List(0),
        setpointBar: setpointBar,
        cns: cns,
        decoStopDepthMeters: decoStopDepthMeters,
        decoTimeSeconds: decoTimeSeconds,
        ttsSeconds: ttsSeconds,
        gasMixIndex: gasMixIndex,
        statusFlags: statusFlags,
      );
}

/// Two cells and a 1.3 bar setpoint, unlike the samples in the
/// [_divesoftRepo] Divecomputer file.
SampleSet _twoCellSampleSet({required String diveId}) {
  const n = 4;
  return SampleSet(
    diveId: diveId,
    sampleCount: n,
    sampleIntervalMs: 5000,
    depthMeters: Float32List.fromList([0.0, 4.2, 8.9, 13.5]),
    temperatureCelsius: Float32List.fromList(List.filled(n, 11.0)),
    ppo2Bar: Float32List.fromList(List.filled(n, 1.28)),
    cellMv0: Float32List.fromList(List.filled(n, 61.0)),
    cellMv1: Float32List.fromList(List.filled(n, 60.5)),
    cellMv2: Float32List(n),
    setpointBar: Float32List.fromList(List.filled(n, 1.3)),
    cns: Float32List(n),
    decoStopDepthMeters: Float32List(n),
    decoTimeSeconds: Int32List(n),
    ttsSeconds: Int32List(n),
    gasMixIndex: Uint8List(n),
    statusFlags: Uint8List(n),
  );
}

/// Two distinct Subsurface sites at the exact same coordinates, as a real
/// repository has them.
const _shoreHex = 'aaaa0001';
const _platformHex = 'aaaa0002';
Map<String, List<SsLine>> _sharedGpsSites() => {
      _shoreHex: parseSubsurfaceFile(
        'name "Quarry North - Shore entry"\n'
        'description ""\n'
        'notes ""\n'
        'gps 52.123450 4.567890\n',
        kind: SubsurfaceFileKind.site,
      ).lines,
      _platformHex: parseSubsurfaceFile(
        'name "Quarry North - Platform"\n'
        'description ""\n'
        'notes ""\n'
        'gps 52.123450 4.567890\n',
        kind: SubsurfaceFileKind.site,
      ).lines,
    };

/// Plan one existing dive whose Dive-NNN on the remote is [existingText],
/// with [annotation] as CCRLog's annotation and no cylinders.
SyncPlan _planAgainst(
  String existingText,
  DiveAnnotation annotation, {
  Map<String, List<SsLine>> existingSites = const {},
}) {
  final bundle = _bundle(
    diveId: _diveIdA,
    annotation: annotation,
    gasMixes: const [],
  );
  return SyncPlanner().plan(
    ccrlogDives: [bundle],
    existingDivesBySerialAndStart: {
      (serial: bundle.dive.dcSerial, startTime: bundle.dive.startTime):
          ExistingRemoteDive(
        folderSegments: ['2026', '04', '19-Sun-15=18=45'],
        diveNumber: 42,
        serial: bundle.dive.dcSerial,
        startTime: bundle.dive.startTime,
        diveLines: parseSubsurfaceFile(
          existingText,
          kind: SubsurfaceFileKind.dive,
        ).lines,
      ),
    },
    existingMaxDiveNumber: 42,
    existingTopLevel: const [],
    existingSites: existingSites,
  );
}

// ── helpers ──────────────────────────────────────────────────────────

// First 8 chars of these ids must be distinct — the mapper's
// fingerprint key uses `diveid=${id.substring(0, 8)}`, so two bundles
// with the same prefix collapse into one fingerprint.
const _diveIdA = 'aaaaaaaa-1111-2222-3333-444444444444';
const _diveIdB = 'bbbbbbbb-1111-2222-3333-444444444444';
const _diveIdC = 'cccccccc-1111-2222-3333-444444444444';

CcrlogDiveBundle _bundle({
  required String diveId,
  int startTime = 1776611925,
  DiveAnnotation? annotation,
  List<SubsurfaceDiveComputerInput>? userDiveComputers,
  List<DiveGasMix>? gasMixes,
  int dcSerial = 0xb89641e4,
  String? dcVendor,
  String? dcProduct,
  int? dcFamily,
  SampleSet? samples,
}) {
  final dive = _ccrPetrelDive(
      diveId: diveId,
      startTime: startTime,
      dcSerial: dcSerial,
      dcVendor: dcVendor,
      dcProduct: dcProduct,
      dcFamily: dcFamily);
  return CcrlogDiveBundle(
    dive: dive,
    samples: samples ?? _smallSampleSet(diveId: diveId),
    annotation: annotation,
    gasMixes: gasMixes ?? _threeGasMixes(),
    tanks: const [],
    cylindersByMixIndex: const {},
    userDiveComputers: userDiveComputers ?? const [],
  );
}

SubsurfaceDiveInput _ccrPetrelDive({
  required String diveId,
  int startTime = 1776611925,
  int dcSerial = 0xb89641e4,
  String? dcVendor,
  String? dcProduct,
  int? dcFamily,
}) {
  return SubsurfaceDiveInput(
    id: diveId,
    dcSerial: dcSerial,
    dcVendor: dcVendor,
    dcProduct: dcProduct,
    dcFamily: dcFamily,
    dcDiveNumber: 705,
    startTime: startTime,
    durationSeconds: 3450,
    maxDepthMm: 18000,
    diveMode: 0,
    gfLow: 50,
    gfHigh: 95,
    atmosphericPressureMbar: 1013,
    waterDensity: 1025,
    logVersion: 17,
    dcModel: 3,
    dcFirmware: 0xa3,
    configuredStackSeconds: 25200,
    stackRemainingAtStartSeconds: 10847,
    stackRemainingAtEndSeconds: 7347,
  );
}

SubsurfaceDiveComputerInput _diveComputer({required int serial}) {
  return SubsurfaceDiveComputerInput(
    serial: serial,
    model: 3,
    nickname: 'Petrel 3',
    dcVendor: 'Shearwater',
    dcFamily: null,
  );
}

DiveAnnotation _testAnnotation({int? rating, String? notes}) =>
    DiveAnnotation(
      diveId: _diveIdA,
      rating: rating,
      notes: notes,
      createdAt: DateTime.utc(2026, 5, 1),
      updatedAt: DateTime.utc(2026, 5, 1),
    );

DiveAnnotation _annotation({
  required String diveId,
  String? siteName,
  double? siteLatitude,
  double? siteLongitude,
}) {
  final now = DateTime.fromMillisecondsSinceEpoch(0);
  return DiveAnnotation(
    diveId: diveId,
    siteName: siteName,
    siteLatitude: siteLatitude,
    siteLongitude: siteLongitude,
    createdAt: now,
    updatedAt: now,
  );
}

List<DiveGasMix> _threeGasMixes() => [
      DiveGasMix(oxygenPercent: 18, heliumPercent: 23, isDiluent: true),
      DiveGasMix(oxygenPercent: 50, heliumPercent: 0, isDiluent: false),
      DiveGasMix(oxygenPercent: 99, heliumPercent: 0, isDiluent: false),
    ];

SampleSet _smallSampleSet({required String diveId}) {
  const n = 6;
  return SampleSet(
    diveId: diveId,
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
