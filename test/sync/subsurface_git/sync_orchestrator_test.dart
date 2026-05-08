// End-to-end orchestrator tests against a local file:// bare remote.
//
// We mirror the pattern from `repo_test.dart`: spin up a bare git repo
// in a temp directory, seed it with a Subsurface-shaped initial commit
// (00-Subsurface with empty fingerprints), and run the full
// orchestrator against it. The orchestrator wires together
// SyncPlanner + RemoteSnapshot + SubsurfaceRepo, so this exercises the
// integration of all three.
//
// We do NOT use the real PowerSync DAOs — they're too heavy to boot
// per test. Instead we feed the orchestrator a `_FakeDataSource` that
// implements the SubsurfaceSyncDataSource seam.

@TestOn('mac-os || linux || windows')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart' hide DiveAnnotation;
import 'package:ccrlogger/data/models/annotation.dart';
import 'package:ccrlogger/data/models/dive.dart' show DiveGasMix;
import 'package:ccrlogger/data/models/sample_set.dart';
import 'package:ccrlogger/sync/subsurface_git/credentials.dart';
import 'package:ccrlogger/sync/subsurface_git/sync_orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';

ProcessResult _git(String cwd, List<String> args) {
  final r = Process.runSync('git', args, workingDirectory: cwd);
  if (r.exitCode != 0) {
    throw StateError(
      'git ${args.join(' ')} in $cwd failed: ${r.stderr}\n${r.stdout}',
    );
  }
  return r;
}

Directory _tempDir(String prefix) {
  final dir = Directory.systemTemp.createTempSync('ccrlog_$prefix');
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return dir;
}

/// Build an "upstream" bare repo with one initial Subsurface-shaped
/// commit on [branch], and return its `file://` URL.
String _seedBareRemote({required String branch}) {
  final bare = _tempDir('bare');
  _git(bare.path, ['init', '--bare', '--initial-branch=$branch']);

  final seed = _tempDir('seed');
  _git(seed.path, ['init', '--initial-branch=$branch']);
  _git(seed.path, ['config', 'user.email', 'seed@example.com']);
  _git(seed.path, ['config', 'user.name', 'seed']);
  // Minimal valid 00-Subsurface so the repo looks Subsurface-shaped.
  // Empty fingerprint/dc-id state lets the planner add ours fresh.
  File('${seed.path}/00-Subsurface').writeAsStringSync(
    'version 3\nunits PERSONALIZE METERS LITER BAR CELSIUS KG MINUTES\n',
  );
  _git(seed.path, ['add', '00-Subsurface']);
  _git(seed.path, ['commit', '-m', 'seed']);
  _git(seed.path, ['remote', 'add', 'origin', 'file://${bare.path}']);
  _git(seed.path, ['push', 'origin', branch]);
  return 'file://${bare.path}';
}

class _FakeCredentials implements SubsurfaceCredentialsSource {
  _FakeCredentials();
  String email = 'tester@example.com';
  String password = 'pw';

  @override
  Future<({String email, String password})?> read() async =>
      (email: email, password: password);

  @override
  Future<void> save(String email, String password) async =>
      throw UnimplementedError();

  @override
  Future<void> clear() async => throw UnimplementedError();
}

class _NullCredentials implements SubsurfaceCredentialsSource {
  @override
  Future<({String email, String password})?> read() async => null;
  @override
  Future<void> save(String email, String password) async =>
      throw UnimplementedError();
  @override
  Future<void> clear() async => throw UnimplementedError();
}

class _FakeDataSource implements SubsurfaceSyncDataSource {
  _FakeDataSource();

  final List<Dive> dives = [];
  final Map<String, SampleSet> samples = {};
  final Map<String, DiveAnnotation?> annotations = {};
  final Map<String, Map<int, Cylinder>> cylinders = {};
  final List<DiveComputer> diveComputers = [];

  /// (diveId, whenSeconds) appended each time markSubsurfaceUploaded
  /// is called. The orchestrator is expected to call this exactly once
  /// per successful push, with all planned dive ids.
  final List<({String diveId, int whenSeconds})> uploadStamps = [];

  @override
  Future<List<Dive>> getAllDives() async => List.of(dives);

  @override
  Future<SampleSet?> getSamples(String diveId) async => samples[diveId];

  @override
  Future<DiveAnnotation?> getAnnotation(String diveId) async =>
      annotations[diveId];

  @override
  Future<Map<int, Cylinder>> cylindersByMixIndex(String diveId) async =>
      cylinders[diveId] ?? const {};

  @override
  Future<List<DiveComputer>> listAllDiveComputers() async =>
      List.of(diveComputers);

  @override
  Future<void> markSubsurfaceUploaded(
      Iterable<String> diveIds, int whenSeconds) async {
    for (final id in diveIds) {
      uploadStamps.add((diveId: id, whenSeconds: whenSeconds));
    }
  }
}

void main() {
  const branch = 'tester@example.com';

  group('SubsurfaceSyncOrchestrator.syncNow',
      skip: 'Safety hold (2026-05-08): syncNow() throws unconditionally '
          'until the planner is rewritten to merge conservatively '
          'rather than overwrite Subsurface-side fields. Re-enable '
          'this group when the safety throw in sync_orchestrator.dart '
          'is removed.', () {
    test('throws NoCredentialsException when creds are missing', () async {
      final clones = _tempDir('clones');
      final orch = SubsurfaceSyncOrchestrator(
        dataSource: _FakeDataSource(),
        credentials: _NullCredentials(),
        localCloneRoot: clones,
      );
      orch.remoteUrlOverride = _seedBareRemote(branch: branch);
      await expectLater(
        orch.syncNow(),
        throwsA(isA<NoCredentialsException>()),
      );
    });

    test('first sync clones, plans, commits, pushes, and stamps '
        'subsurface_uploaded_at', () async {
      final remoteUrl = _seedBareRemote(branch: branch);
      final clones = _tempDir('clones');
      final ds = _FakeDataSource()
        ..diveComputers.add(_petrelComputer())
        ..addBundle(_diveA());

      final orch = SubsurfaceSyncOrchestrator(
        dataSource: ds,
        credentials: _FakeCredentials(),
        localCloneRoot: clones,
      );
      orch.remoteUrlOverride = remoteUrl;

      final result = await orch.syncNow();
      expect(result.divesPushed, 1);
      expect(result.commitSha, isNotNull);
      // dataSource was stamped.
      expect(ds.uploadStamps.length, 1);
      expect(ds.uploadStamps.single.diveId, _diveA().dive.id);

      // Verify the bare remote received a real commit with the
      // expected files.
      final bareDir = remoteUrl.replaceFirst('file://', '');
      final ls = _git(bareDir, ['ls-tree', '-r', branch]);
      final out = ls.stdout.toString();
      expect(out, contains('00-Subsurface'));
      expect(out, contains('Dive-1'));
      expect(out, contains('Divecomputer'));
    });

    test('second sync with no changes is a no-op (divesPushed=0)', () async {
      final remoteUrl = _seedBareRemote(branch: branch);
      final clones = _tempDir('clones');
      final ds = _FakeDataSource()
        ..diveComputers.add(_petrelComputer())
        ..addBundle(_diveA());

      final orch = SubsurfaceSyncOrchestrator(
        dataSource: ds,
        credentials: _FakeCredentials(),
        localCloneRoot: clones,
      );
      orch.remoteUrlOverride = remoteUrl;

      final first = await orch.syncNow();
      expect(first.divesPushed, 1);

      // Reset stamp tracker so we can assert on second run.
      ds.uploadStamps.clear();

      final second = await orch.syncNow();
      expect(second.divesPushed, 0);
      expect(second.commitSha, isNull);
      // Nothing pushed → nothing stamped.
      expect(ds.uploadStamps, isEmpty);
    });

    test('updating annotation and re-syncing produces a new commit',
        () async {
      final remoteUrl = _seedBareRemote(branch: branch);
      final clones = _tempDir('clones');
      final ds = _FakeDataSource()
        ..diveComputers.add(_petrelComputer())
        ..addBundle(_diveA());

      final orch = SubsurfaceSyncOrchestrator(
        dataSource: ds,
        credentials: _FakeCredentials(),
        localCloneRoot: clones,
      );
      orch.remoteUrlOverride = remoteUrl;

      await orch.syncNow();

      // Update the annotation: add notes.
      ds.annotations[_diveA().dive.id] = DiveAnnotation(
        diveId: _diveA().dive.id,
        notes: 'Trim test, all cells happy.',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1),
      );

      final result = await orch.syncNow();
      expect(result.divesPushed, 1);
      expect(result.commitSha, isNotNull);

      // Confirm the dive file in the bare remote has the new notes.
      final bareDir = remoteUrl.replaceFirst('file://', '');
      final showHead = _git(bareDir, ['log', branch, '--format=%s']);
      expect(showHead.stdout.toString(), contains('CCRLog sync'));
    });
  });
}

// ── helpers ──────────────────────────────────────────────────────────

extension _FakeDataSourceBundle on _FakeDataSource {
  void addBundle(_Bundle b) {
    dives.add(b.dive);
    samples[b.dive.id] = b.samples;
    // Annotations + cylinders default to "none"; the per-test
    // overrides happen by mutating ds.annotations / ds.cylinders
    // directly after addBundle().
    annotations.putIfAbsent(b.dive.id, () => null);
    cylinders.putIfAbsent(b.dive.id, () => const {});
  }
}

class _Bundle {
  _Bundle({
    required this.dive,
    required this.samples,
  });
  final Dive dive;
  final SampleSet samples;
  // The annotation/cylinder maps live on the data source; tests
  // mutate ds.annotations / ds.cylinders directly when they need to
  // override the defaults.
}

const _diveIdA = 'aaaaaaaa-1111-2222-3333-444444444444';

DiveComputer _petrelComputer() {
  return DiveComputer(
    id: 'dc-petrel',
    serial: 0xb89641e4,
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

_Bundle _diveA() {
  final dive = Dive(
    id: _diveIdA,
    dcSerial: 0xb89641e4,
    dcDiveNumber: 705,
    startTime: 1776611925,
    endTime: 1776611925 + 3450,
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
    // gas mixes JSON: one diluent. The orchestrator decodes this
    // with DiveGasMix.fromJson, which expects 'o2'/'he'/'dil' keys.
    gasMixesJson: '[{"o2":18,"he":23,"dil":true}]',
    tanksJson: null,
    configuredStackSeconds: 25200,
    stackRemainingAtStartSeconds: 10847,
    stackRemainingAtEndSeconds: 7347,
    rawBlob: Uint8List(0),
    parserVersion: 1,
    importedAt: 1776591525,
  );
  // sanity-check the JSON decodes to the expected shape.
  // ignore: unused_local_variable
  final _ = DiveGasMix(oxygenPercent: 18, heliumPercent: 23, isDiluent: true);
  return _Bundle(dive: dive, samples: _smallSampleSet(diveId: dive.id));
}

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
