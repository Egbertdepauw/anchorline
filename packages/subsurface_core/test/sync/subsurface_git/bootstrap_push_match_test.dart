// A dive the bootstrap imported from Subsurface must be matched to its
// own remote folder when it is pushed back. If it is not, the planner
// takes the new-dive branch: it writes `<same folder>/Dive-<next>` next
// to the original `Dive-NNN` and overwrites that folder's
// `Divecomputer` file with CCRLog's emission.
//
// Each test runs the real chain against the fixture repository:
// `RemoteSnapshot.fromFiles` → the read mapper the bootstrap uses →
// a `CcrlogDiveBundle` built the way the orchestrator builds one from
// the stored row → `SyncPlanner.plan`.

@TestOn('mac-os || linux || windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:subsurface_core/data/models/dive.dart';
import 'package:subsurface_core/sync/subsurface_git/format/subsurface_format.dart';
import 'package:subsurface_core/sync/subsurface_git/format/subsurface_parser.dart';
import 'package:subsurface_core/sync/subsurface_git/remote_snapshot.dart';
import 'package:subsurface_core/sync/subsurface_git/subsurface_to_ccrlog_mapper.dart';
import 'package:subsurface_core/sync/subsurface_git/sync_inputs.dart';
import 'package:subsurface_core/sync/subsurface_git/sync_planner.dart';
import 'package:test/test.dart';

const _fixturesRoot = 'test/fixtures/subsurface';

/// The manually added 2004 dive: no `model` line, no `Serial`.
const _manualFolder = '2004/06/19-Sat-09=00=00';

void main() {
  group('pushing a bootstrapped dive back to its own repository', () {
    test('a manual dive (no Serial) is matched to its remote folder', () {
      final files = _fixtureFiles();
      final snapshot = RemoteSnapshot.fromFiles(files);
      final bundle = _bootstrapBundle(files, _manualFolder);

      // The bootstrap stores a dive without a Serial under serial 0.
      expect(bundle.dive.dcSerial, 0);

      final plan = _plan(snapshot, [bundle]);

      expect(plan.stats.newDives, 0,
          reason: 'the dive already exists remotely');
      expect(plan.filesToWrite.keys,
          isNot(contains('$_manualFolder/Divecomputer')));
      final diveFiles = plan.filesToWrite.keys
          .where((k) => k.startsWith('$_manualFolder/Dive-'));
      expect(diveFiles, everyElement('$_manualFolder/Dive-13'),
          reason: 'no second Dive-NNN in the folder');
    });

    test('every fixture dive matches its own folder and writes no '
        'Divecomputer', () {
      final files = _fixtureFiles();
      final snapshot = RemoteSnapshot.fromFiles(files);
      final folders = _diveFolders(files);
      final bundles = [
        for (final folder in folders) _bootstrapBundle(files, folder),
      ];

      final plan = _plan(snapshot, bundles);

      expect(plan.stats.newDives, 0);
      expect(plan.stats.abortedDives, 0);
      for (final folder in folders) {
        expect(plan.filesToWrite.keys,
            isNot(contains('$folder/Divecomputer')),
            reason: folder);
      }
      // No Dive-NNN outside the numbers the repository already has.
      final existingDiveFiles = files.keys
          .where((k) => p.posix.basename(k).startsWith('Dive-'))
          .toSet();
      final writtenDiveFiles = plan.filesToWrite.keys
          .where((k) => p.posix.basename(k).startsWith('Dive-'));
      for (final path in writtenDiveFiles) {
        expect(existingDiveFiles, contains(path), reason: path);
      }
    });

    // Once every dive matches, the owned-line merge decides whether its
    // Dive-NNN is rewritten. A dive bootstrapped from the repository holds
    // what the repository holds, so pushing it back must leave every
    // Dive-NNN as it is. The fixture dives lack `divemaster` and `suit`
    // lines, which the merge used to append as `divemaster ""` and
    // `suit ""`.
    test('every fixture dive pushed back unchanged is skipped', () {
      final files = _fixtureFiles();
      final snapshot = RemoteSnapshot.fromFiles(files);
      final folders = _diveFolders(files);
      final bundles = [
        for (final folder in folders) _bootstrapBundle(files, folder),
      ];

      final plan = _plan(snapshot, bundles);

      expect(plan.stats.skippedDives, folders.length);
      expect(plan.stats.updatedDives, 0);
      expect(plan.diveIdsPlanned, isEmpty);
      final writtenDiveFiles = [
        for (final path in plan.filesToWrite.keys)
          if (p.posix.basename(path).startsWith('Dive-'))
            '$path:\n${_lineDiff(files[path], plan.filesToWrite[path]!)}',
      ];
      expect(writtenDiveFiles, isEmpty);
    });

    // Distinct Subsurface sites can share the exact same GPS: a real
    // repository has several such pairs. Each bootstrapped dive carries
    // its own site's name, and pushing them back must leave both Site
    // files as they are. The planner used to look the site up by
    // coordinates only, so one site's name was written into the other.
    test('two sites with the same GPS are not renamed on a round trip', () {
      // Dive-705 and Dive-656 point at these two sites.
      const siteA = '01-Divesites/Site-456b7d53';
      const siteB = '01-Divesites/Site-d13686a9';
      final files = {
        ..._fixtureFiles(),
        siteA: 'name "Quarry North - Shore entry"\n'
            'description ""\n'
            'notes ""\n'
            'gps 52.123450 4.567890\n'
            'geo cat 2 origin 2 "Nederland"\n',
        siteB: 'name "Quarry North - Platform"\n'
            'description "Second entry point"\n'
            'notes ""\n'
            'gps 52.123450 4.567890\n'
            'geo cat 2 origin 2 "Nederland"\n',
      };
      final snapshot = RemoteSnapshot.fromFiles(files);
      final folders = _diveFolders(files);
      final bundles = [
        for (final folder in folders) _bootstrapBundle(files, folder),
      ];
      // Both dives were bootstrapped with their own site.
      final siteNames = {
        for (final b in bundles)
          if (b.annotation?.siteName != null) b.annotation!.siteName!,
      };
      expect(siteNames, {
        'Quarry North - Shore entry',
        'Quarry North - Platform',
      });

      final plan = _plan(snapshot, bundles);

      final changedSites = [
        for (final path in plan.filesToWrite.keys)
          if (path.startsWith('01-Divesites/') &&
              plan.filesToWrite[path] != files[path])
            '$path:\n${_lineDiff(files[path], plan.filesToWrite[path]!)}',
      ];
      expect(changedSites, isEmpty);
      // A Site file that would be written back unchanged is not staged.
      expect(
        plan.filesToWrite.keys.where((k) => k.startsWith('01-Divesites/')),
        isEmpty,
      );
      expect(plan.stats.updatedDives, 0);
    });

    // Subsurface itself writes `SP change` events too: the real repository
    // has a serial-less `model "Perdix 2"` CCR dive with
    // `event 0:00 type=20 value=1100 name="SP change"`. The planner's
    // rewrite exception for CCRLog-written Divecomputer files must not
    // take that file for one of ours.
    test('a serial-less Divecomputer with an SP change event is not '
        'rewritten', () {
      const folder = '2020/08/18-Tue-16=00=27';
      final files = _withSpChangeEvent(_fixtureFiles(), folder);
      final snapshot = RemoteSnapshot.fromFiles(files);
      final bundle = _bootstrapBundle(files, folder);
      expect(bundle.dive.dcSerial, 0);

      final plan = _plan(snapshot, [bundle]);

      expect(plan.stats.newDives, 0);
      expect(plan.filesToWrite.keys, isNot(contains('$folder/Divecomputer')));
    });

    test('a Divecomputer with a Serial and an SP change event is still '
        'rewritten from the mapper output', () {
      const folder = '2026/04/04-Sat-13=30=15';
      final files = _withSpChangeEvent(_fixtureFiles(), folder);
      final snapshot = RemoteSnapshot.fromFiles(files);
      final bundle = _bootstrapBundle(files, folder);
      expect(bundle.dive.dcSerial, 0xb89641e4);

      final plan = _plan(snapshot, [bundle]);

      expect(plan.stats.newDives, 0);
      expect(plan.filesToWrite.keys, contains('$folder/Divecomputer'));
      expect(plan.diveIdsPlanned, [bundle.dive.id]);
    });

    // New dives are numbered past the dives the index holds, so a manual
    // dive left out of the index could have its number handed out again.
    test('a new dive is numbered past a manual dive with the highest '
        'number', () {
      const petrel = '2026/04/27-Mon-11=33=43'; // Dive-710
      final source = _fixtureFiles();
      final newDive = _bootstrapBundle(source, petrel);
      // The remote without the Petrel dive (highest Petrel is now 705),
      // plus a manual dive numbered 706.
      final files = {
        for (final e in source.entries)
          if (!e.key.startsWith('$petrel/')) e.key: e.value,
        '2026/04/20-Mon-10=00=00/Dive-706':
            source['2020/08/18-Tue-16=00=27/Dive-365']!,
        '2026/04/20-Mon-10=00=00/Divecomputer':
            source['2020/08/18-Tue-16=00=27/Divecomputer']!,
      };
      final snapshot = RemoteSnapshot.fromFiles(files);

      final plan = _plan(snapshot, [newDive]);

      expect(plan.stats.newDives, 1);
      expect(plan.filesToWrite.keys, contains('$petrel/Dive-707'));
    });
  });
}

/// The lines [after] drops (`-`) and adds (`+`) relative to [before], for
/// a readable failure message.
String _lineDiff(String? before, String after) {
  final b = const LineSplitter().convert(before ?? '');
  final a = const LineSplitter().convert(after);
  return [
    for (final l in b)
      if (!a.contains(l)) '  - $l',
    for (final l in a)
      if (!b.contains(l)) '  + $l',
  ].join('\n');
}

/// [files] with an `SP change` event added to [folder]'s Divecomputer,
/// ahead of its first sample line.
Map<String, String> _withSpChangeEvent(
  Map<String, String> files,
  String folder,
) {
  final path = '$folder/Divecomputer';
  final lines = const LineSplitter().convert(files[path]!);
  final firstSample = lines.indexWhere((l) => l.startsWith(' '));
  lines.insert(firstSample, 'event 0:00 type=20 value=1100 name="SP change"');
  return {...files, path: '${lines.join('\n')}\n'};
}

SyncPlan _plan(RemoteSnapshotData snapshot, List<CcrlogDiveBundle> bundles) =>
    SyncPlanner().plan(
      ccrlogDives: bundles,
      existingDivesBySerialAndStart: snapshot.existingDivesBySerialAndStart,
      existingMaxDiveNumber: snapshot.existingMaxDiveNumber,
      existingTopLevel: snapshot.existingTopLevel,
      existingSites: snapshot.existingSites,
    );

// ── Fixture repository ────────────────────────────────────────────────

/// The fixture tree re-keyed into a real repository's layout (Site-* under
/// `01-Divesites/`, dives directly under `<YYYY>/`), as POSIX paths.
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

List<String> _diveFolders(Map<String, String> files) {
  final out = <String>{};
  for (final path in files.keys) {
    final segments = path.split('/');
    if (segments.length == 4 && RegExp(r'^\d{4}$').hasMatch(segments[0])) {
      out.add(segments.sublist(0, 3).join('/'));
    }
  }
  return out.toList()..sort();
}

// ── Bootstrap, as `SubsurfaceBootstrapImporter` does it ────────────────

/// Map one folder the way the bootstrap importer does, then build the
/// bundle the orchestrator would build from the stored row.
CcrlogDiveBundle _bootstrapBundle(Map<String, String> files, String folder) {
  int? diveNumber;
  String? diveText;
  String? dcText;
  for (final entry in files.entries) {
    if (p.posix.dirname(entry.key) != folder) continue;
    final name = p.posix.basename(entry.key);
    if (name.startsWith('Dive-')) {
      final n = int.parse(name.substring('Dive-'.length));
      if (diveNumber == null || n > diveNumber) {
        diveNumber = n;
        diveText = entry.value;
      }
    } else if (name == 'Divecomputer') {
      dcText = entry.value;
    }
  }
  final diveLines =
      parseSubsurfaceFile(diveText!, kind: SubsurfaceFileKind.dive).lines;
  final dcLines =
      parseSubsurfaceFile(dcText!, kind: SubsurfaceFileKind.divecomputer)
          .lines;

  List<SsLine>? siteLines;
  for (final l in diveLines) {
    if (l is ScalarLine && l.key == 'divesiteid') {
      final site = files['01-Divesites/Site-${l.value.trim()}'];
      if (site != null) {
        siteLines =
            parseSubsurfaceFile(site, kind: SubsurfaceFileKind.site).lines;
      }
    }
  }

  final imported = SubsurfaceToCcrlogMapper().mapDive(
    diveLines: diveLines,
    divecomputerLines: dcLines,
    siteLines: siteLines,
    startTime: _folderStartTime(folder),
    subsurfaceDiveNumber: diveNumber!,
  )!;
  final dive = imported.converted.dive;
  return CcrlogDiveBundle(
    dive: _rowInput(dive),
    samples: imported.converted.samples,
    annotation: imported.annotation,
    gasMixes: dive.gasMixes,
    tanks: dive.tanks,
    // The bootstrap does not link cylinders (v1 out of scope).
    cylindersByMixIndex: const {},
    userDiveComputers: const [],
  );
}

/// `YYYY/MM/DD-Day-HH=MM=SS` → UTC, as the bootstrap parses it.
DateTime _folderStartTime(String folder) {
  final s = folder.split('/');
  final m = RegExp(r'^(\d{2})-[A-Za-z]{3}-(\d{2})=(\d{2})=(\d{2})$')
      .firstMatch(s[2])!;
  return DateTime.utc(
    int.parse(s[0]),
    int.parse(s[1]),
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    int.parse(m.group(4)!),
  );
}

/// The `SubsurfaceDiveInput` the orchestrator builds from the row
/// `DiveDao.importDive` stores for [d].
SubsurfaceDiveInput _rowInput(Dive d) => SubsurfaceDiveInput(
      id: d.id,
      dcSerial: d.dcSerial,
      dcDiveNumber: d.dcDiveNumber,
      startTime: d.startTime.millisecondsSinceEpoch ~/ 1000,
      durationSeconds: d.duration.inSeconds,
      maxDepthMm: (d.maxDepthMeters * 1000).round(),
      diveMode: d.diveMode.value,
      dcModel: d.dcModel.index,
      dcVendor: d.dcVendor,
      dcFamily: d.dcFamily,
      logVersion: d.logVersion,
      atmosphericPressureMbar: d.atmosphericPressureMbar,
      waterDensity: d.waterDensityKgM3,
      gfLow: d.gfLow,
      gfHigh: d.gfHigh,
      sensorCalibrationJson: d.sensorCalibration.isEmpty
          ? null
          : jsonEncode(d.sensorCalibration),
      configuredStackSeconds: d.configuredStackSeconds,
      stackRemainingAtStartSeconds: d.stackRemainingAtStartSeconds,
      stackRemainingAtEndSeconds: d.stackRemainingAtEndSeconds,
    );
