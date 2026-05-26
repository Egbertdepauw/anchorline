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

import 'package:ccrlogger/data/db/database.dart' hide DiveAnnotation;
import 'package:ccrlogger/data/models/annotation.dart';
import 'package:ccrlogger/data/models/dive.dart' show DiveGasMix;
import 'package:ccrlogger/data/models/sample_set.dart';
import 'package:ccrlogger/sync/subsurface_git/format/subsurface_parser.dart';
import 'package:ccrlogger/sync/subsurface_git/mapper.dart';
import 'package:ccrlogger/sync/subsurface_git/sync_planner.dart';
import 'package:flutter_test/flutter_test.dart';

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

      // The site write goes to the EXISTING Subsurface UUID.
      expect(
        plan.filesToWrite.keys,
        contains('01-Divesites/Site-$subsurfaceHex'),
      );
      // No orphan under CCRLog's SHA-256 hash was created.
      final orphanCandidates = plan.filesToWrite.keys
          .where((k) =>
              k.startsWith('01-Divesites/') && !k.endsWith(subsurfaceHex))
          .toList();
      expect(orphanCandidates, isEmpty,
          reason: 'CCRLog must not create duplicate Site files for sites '
              'Subsurface already has under its own UUID.');
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
      final bumped = Dive(
        id: bundle.dive.id,
        dcSerial: bundle.dive.dcSerial,
        dcDiveNumber: 1146,
        startTime: bundle.dive.startTime,
        endTime: bundle.dive.endTime,
        utcOffsetMinutes: bundle.dive.utcOffsetMinutes,
        durationSeconds: bundle.dive.durationSeconds,
        maxDepthMm: bundle.dive.maxDepthMm,
        diveMode: bundle.dive.diveMode,
        decoModel: bundle.dive.decoModel,
        gfLow: bundle.dive.gfLow,
        gfHigh: bundle.dive.gfHigh,
        atmosphericPressureMbar: bundle.dive.atmosphericPressureMbar,
        waterDensity: bundle.dive.waterDensity,
        logVersion: bundle.dive.logVersion,
        dcModel: bundle.dive.dcModel,
        dcFirmware: bundle.dive.dcFirmware,
        sampleIntervalMs: bundle.dive.sampleIntervalMs,
        gasMixesJson: bundle.dive.gasMixesJson,
        tanksJson: bundle.dive.tanksJson,
        configuredStackSeconds: bundle.dive.configuredStackSeconds,
        stackRemainingAtStartSeconds: bundle.dive.stackRemainingAtStartSeconds,
        stackRemainingAtEndSeconds: bundle.dive.stackRemainingAtEndSeconds,
        rawBlob: bundle.dive.rawBlob,
        parserVersion: bundle.dive.parserVersion,
        importedAt: bundle.dive.importedAt,
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
  });
}

// ── helpers ──────────────────────────────────────────────────────────

// First 8 chars of these ids must be distinct — the mapper's
// fingerprint key uses `diveid=${id.substring(0, 8)}`, so two bundles
// with the same prefix collapse into one fingerprint.
const _diveIdA = 'aaaaaaaa-1111-2222-3333-444444444444';
const _diveIdB = 'bbbbbbbb-1111-2222-3333-444444444444';

CcrlogDiveBundle _bundle({
  required String diveId,
  int startTime = 1776611925,
  DiveAnnotation? annotation,
  List<DiveComputer>? userDiveComputers,
  List<DiveGasMix>? gasMixes,
}) {
  final dive = _ccrPetrelDive(diveId: diveId, startTime: startTime);
  return CcrlogDiveBundle(
    dive: dive,
    samples: _smallSampleSet(diveId: diveId),
    annotation: annotation,
    gasMixes: gasMixes ?? _threeGasMixes(),
    tanks: const [],
    cylindersByMixIndex: const {},
    userDiveComputers: userDiveComputers ?? const [],
  );
}

Dive _ccrPetrelDive({
  required String diveId,
  int startTime = 1776611925,
}) {
  return Dive(
    id: diveId,
    dcSerial: 0xb89641e4,
    dcDiveNumber: 705,
    startTime: startTime,
    endTime: startTime + 3450,
    utcOffsetMinutes: null,
    durationSeconds: 3450,
    maxDepthMm: 18000,
    diveMode: 0,
    decoModel: 0,
    gfLow: 50,
    gfHigh: 95,
    atmosphericPressureMbar: 1013,
    waterDensity: 1025,
    logVersion: 17,
    dcModel: 3,
    dcFirmware: 0xa3,
    sampleIntervalMs: 10000,
    gasMixesJson: '',
    tanksJson: null,
    configuredStackSeconds: 25200,
    stackRemainingAtStartSeconds: 10847,
    stackRemainingAtEndSeconds: 7347,
    rawBlob: Uint8List(0),
    parserVersion: 1,
    importedAt: 1776591525,
  );
}

DiveComputer _diveComputer({required int serial}) {
  return DiveComputer(
    id: 'dc-${serial.toRadixString(16)}',
    serial: serial,
    model: 3,
    firmwareVersion: 0xa3,
    nickname: 'Petrel 3',
    createdAt: 0,
    updatedAt: 0,
    deletedAt: null,
    version: 1,
    syncStatus: 0,
    ownerId: null,
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
