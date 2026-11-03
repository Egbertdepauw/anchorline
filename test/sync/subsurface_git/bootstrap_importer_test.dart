// End-to-end-ish tests for the read-direction bootstrap importer. We
// substitute the git layer with a `_FakeRepo` so these tests don't need
// libgit2 or a network — the importer only calls `ensureCloned()` and
// `pull()` and otherwise walks the filesystem, so faking the repo is
// enough to exercise everything else.
//
// In production the importer is wired against a real [SubsurfaceRepo]
// pointed at Subsurface Cloud. The bypassed git seam is covered
// separately by `repo_test.dart`.

import 'dart:io';
import 'dart:typed_data';

import 'package:subsurface_core/data/models/annotation.dart';
import 'package:subsurface_core/shearwater/parser/dive_converter.dart'
    show ConvertedDive;
import 'package:ccrlogger/sync/subsurface_git/bootstrap_importer.dart';
import 'package:ccrlogger/sync/subsurface_git/credentials.dart';
import 'package:ccrlogger/sync/subsurface_git/repo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// ── Test doubles ─────────────────────────────────────────────────────

class _FakeCredentials implements SubsurfaceCredentialsSource {
  _FakeCredentials();
  static const _value = (email: 'tester@example.com', password: 'pw');

  @override
  Future<({String email, String password})?> read() async => _value;

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

/// In-memory data source. Records every importDive / upsertAnnotation
/// so tests can assert on counts without needing the real DAOs.
class _FakeBootstrapDataSource implements BootstrapDataSource {
  final Set<({int dcSerial, int startTime})> existing = {};
  final List<ConvertedDive> imported = [];
  final Map<String, DiveAnnotation> annotations = {};

  @override
  Future<Set<({int dcSerial, int startTime})>> existingDiveKeys() async =>
      Set.of(existing);

  @override
  Future<bool> importDive({
    required ConvertedDive converted,
    required Uint8List rawBlob,
    required int parserVersion,
  }) async {
    final key = (
      dcSerial: converted.dive.dcSerial,
      startTime: converted.dive.startTime.millisecondsSinceEpoch ~/ 1000,
    );
    if (existing.contains(key)) return false;
    imported.add(converted);
    existing.add(key);
    return true;
  }

  @override
  Future<void> upsertAnnotation(DiveAnnotation annotation) async {
    annotations[annotation.diveId] = annotation;
  }
}

/// Test-only [SubsurfaceRepo] override. Both action methods are
/// no-ops — the importer's per-dive loop reads files from `localDir`
/// directly, so we just need a real directory at the right path with
/// fixture content already in it.
class _FakeRepo extends SubsurfaceRepo {
  _FakeRepo({
    required super.localDir,
    required super.remoteUrl,
    required super.credentials,
    this.cloneThrows,
    this.pullThrows,
  });

  Object? cloneThrows;
  Object? pullThrows;

  int cloneCalls = 0;
  int pullCalls = 0;

  @override
  Future<void> ensureCloned() async {
    cloneCalls++;
    final t = cloneThrows;
    if (t != null) throw t;
  }

  @override
  Future<void> pull() async {
    pullCalls++;
    final t = pullThrows;
    if (t != null) throw t;
  }
}

// ── Fixture-folder helpers ───────────────────────────────────────────

const _fixturesRoot = 'packages/subsurface_core/test/fixtures/subsurface';

Directory _tempDir(String prefix) {
  final dir = Directory.systemTemp.createTempSync('ccrlog_$prefix');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

/// Copy a fixture dive folder (e.g. `2026/04/04-Sat-13=30=15`) into
/// [repoRoot] under the same relative path. We deep-copy because the
/// importer reads from [repoRoot] directly.
void _copyFixtureDive(Directory repoRoot, String relPath) {
  final src = Directory('$_fixturesRoot/dives/$relPath');
  if (!src.existsSync()) {
    throw StateError('Fixture not found: $relPath');
  }
  final dst = Directory(p.join(repoRoot.path, relPath));
  dst.createSync(recursive: true);
  for (final f in src.listSync()) {
    if (f is File) {
      f.copySync(p.join(dst.path, p.basename(f.path)));
    }
  }
}

/// Copy a fixture site file into `<repo>/01-Divesites/`. By default
/// the destination filename matches the source. Tests pass [destHexId]
/// when the bundled fixture's hex doesn't line up with the dive's
/// `divesiteid` line — we don't have a site fixture for every
/// `divesiteid` referenced in the dive fixtures, so we re-key the
/// content under whatever the dive points at.
void _copyFixtureSite(
  Directory repoRoot,
  String sourceHexId, {
  String? destHexId,
}) {
  final src = File('$_fixturesRoot/sites/Site-$sourceHexId');
  final dstDir = Directory(p.join(repoRoot.path, '01-Divesites'))
    ..createSync(recursive: true);
  final dst = File(p.join(dstDir.path, 'Site-${destHexId ?? sourceHexId}'));
  src.copySync(dst.path);
}

/// Resolve the credential email's `<email>-bootstrap` clone subdir under
/// the importer's clone root. The importer creates this on first run.
Directory _bootstrapClone(Directory cloneRoot, String email) {
  final d = Directory(p.join(cloneRoot.path, '$email-bootstrap'));
  d.createSync(recursive: true);
  return d;
}

/// Build an importer wired to use [_FakeRepo]. The fake repo's
/// `localDir` is `<cloneRoot>/<email>-bootstrap/` — the importer
/// constructs that path itself, so we mirror it here.
SubsurfaceBootstrapImporter _makeImporter({
  required SubsurfaceCredentialsSource credentials,
  required Directory cloneRoot,
  required _FakeBootstrapDataSource dataSource,
  Object? cloneThrows,
  Object? pullThrows,
}) {
  return SubsurfaceBootstrapImporter(
    credentials: credentials,
    localCloneRoot: cloneRoot,
    dataSource: dataSource,
    repoFactory: ({
      required Directory localDir,
      required String remoteUrl,
      required SubsurfaceCredentialsSource credentials,
    }) =>
        _FakeRepo(
      localDir: localDir,
      remoteUrl: remoteUrl,
      credentials: credentials,
      cloneThrows: cloneThrows,
      pullThrows: pullThrows,
    ),
  );
}

void main() {
  // The repo factory bypass means we don't need a git library, so this
  // suite runs on every platform our tests cover.

  group('SubsurfaceBootstrapImporter.import', () {
    test('emits BootstrapFailed(NoCredentialsBootstrapException) when '
        'credentials are missing', () async {
      final cloneRoot = _tempDir('clones');
      final ds = _FakeBootstrapDataSource();
      final imp = _makeImporter(
        credentials: _NullCredentials(),
        cloneRoot: cloneRoot,
        dataSource: ds,
      );

      final events = await imp.import().toList();
      expect(
        events.last,
        isA<BootstrapFailed>().having(
          (e) => e.exception,
          'exception',
          isA<NoCredentialsBootstrapException>(),
        ),
      );
    });

    test('emits BootstrapFailed(AuthFailedBootstrapException) on auth '
        'failure during clone', () async {
      final cloneRoot = _tempDir('clones');
      final ds = _FakeBootstrapDataSource();
      final imp = _makeImporter(
        credentials: _FakeCredentials(),
        cloneRoot: cloneRoot,
        dataSource: ds,
        cloneThrows: GitAuthException('401 unauthorized'),
      );

      final events = await imp.import().toList();
      expect(
        events.last,
        isA<BootstrapFailed>().having(
          (e) => e.exception,
          'exception',
          isA<AuthFailedBootstrapException>(),
        ),
      );
    });

    test('imports every importable dive on a fresh CCRLog', () async {
      final cloneRoot = _tempDir('clones');
      final ds = _FakeBootstrapDataSource();

      // Pre-populate the fake clone dir with 3 importable fixture
      // dives. The fake repo's clone/pull are no-ops, so we must
      // place the files where the importer will look.
      final repoDir = _bootstrapClone(cloneRoot, 'tester@example.com');
      _copyFixtureDive(repoDir, '2026/04/04-Sat-13=30=15');
      _copyFixtureDive(repoDir, '2026/04/27-Mon-11=33=43');
      _copyFixtureDive(repoDir, '2025/05/04-Sun-09=48=36');

      final imp = _makeImporter(
        credentials: _FakeCredentials(),
        cloneRoot: cloneRoot,
        dataSource: ds,
      );

      final events = await imp.import().toList();
      final done = events.last as BootstrapDone;
      expect(done.result.divesImported, 3);
      expect(done.result.divesSkipped, 0);
      expect(done.result.divesUnmappable, 0);

      // Importer also emitted a WalkingRepo event with the count.
      final walking = events.whereType<WalkingRepo>().single;
      expect(walking.totalCandidateDives, 3);

      // And one ImportingDive per candidate.
      expect(events.whereType<ImportingDive>().length, 3);

      // Data source recorded each import.
      expect(ds.imported, hasLength(3));

      // Sanity-check one of the imported dives — the 2026/04/04 fixture
      // is a Petrel 3 CCR with serial 0xb89641e4.
      final petrelDive = ds.imported.firstWhere(
        (d) => d.dive.dcSerial == 0xb89641e4 &&
            d.dive.startTime ==
                DateTime.utc(2026, 04, 04, 13, 30, 15),
      );
      expect(petrelDive.dive.dcDiveNumber, 705);
    });

    test('skips dives CCRLog already has by (dcSerial, startTime)',
        () async {
      final cloneRoot = _tempDir('clones');
      final ds = _FakeBootstrapDataSource()
        // Pre-seed the existing-keys set with the 2026/04/04 dive's
        // identity. This simulates a prior BLE import of the same dive.
        ..existing.add((
          dcSerial: 0xb89641e4,
          startTime: DateTime.utc(2026, 04, 04, 13, 30, 15)
                  .millisecondsSinceEpoch ~/
              1000,
        ));

      final repoDir = _bootstrapClone(cloneRoot, 'tester@example.com');
      _copyFixtureDive(repoDir, '2026/04/04-Sat-13=30=15');
      _copyFixtureDive(repoDir, '2026/04/27-Mon-11=33=43');
      _copyFixtureDive(repoDir, '2025/05/04-Sun-09=48=36');

      final imp = _makeImporter(
        credentials: _FakeCredentials(),
        cloneRoot: cloneRoot,
        dataSource: ds,
      );

      final events = await imp.import().toList();
      final done = events.last as BootstrapDone;
      expect(done.result.divesImported, 2);
      expect(done.result.divesSkipped, 1);
      expect(done.result.divesUnmappable, 0);

      // The 2026/04/04 dive was NOT inserted again.
      final added2026Apr04 = ds.imported.where(
        (d) => d.dive.startTime ==
            DateTime.utc(2026, 04, 04, 13, 30, 15),
      );
      expect(added2026Apr04, isEmpty);
    });

    test('manual-only dives (no model line) import with synthesised DC',
        () async {
      final cloneRoot = _tempDir('clones');
      final ds = _FakeBootstrapDataSource();

      final repoDir = _bootstrapClone(cloneRoot, 'tester@example.com');
      _copyFixtureDive(repoDir, '2004/06/19-Sat-09=00=00'); // ancient manual
      _copyFixtureDive(repoDir, '2026/04/04-Sat-13=30=15'); // real Petrel

      final imp = _makeImporter(
        credentials: _FakeCredentials(),
        cloneRoot: cloneRoot,
        dataSource: ds,
      );

      final events = await imp.import().toList();
      final done = events.last as BootstrapDone;
      // Both dives import — manual one with dcSerial=0, dcModel=unknown.
      // Previously the mapper rejected manual entries; we now synthesise
      // so users don't lose dives that exist in their Subsurface log.
      expect(done.result.divesImported, 2);
      expect(done.result.divesSkipped, 0);
      expect(done.result.divesUnmappable, 0);
    });

    test('site file is consulted via divesiteid and populates annotation',
        () async {
      final cloneRoot = _tempDir('clones');
      final ds = _FakeBootstrapDataSource();

      // The 2025/05/04 dive's `divesiteid` is `d13686a9`. Our bundled
      // site fixtures don't include that hex, so we re-key the
      // Om Sid (0a9f7232) site file under d13686a9 to make the
      // resolver succeed.
      final repoDir = _bootstrapClone(cloneRoot, 'tester@example.com');
      _copyFixtureDive(repoDir, '2025/05/04-Sun-09=48=36');
      _copyFixtureSite(repoDir, '0a9f7232', destHexId: 'd13686a9');

      final imp = _makeImporter(
        credentials: _FakeCredentials(),
        cloneRoot: cloneRoot,
        dataSource: ds,
      );

      final events = await imp.import().toList();
      final done = events.last as BootstrapDone;
      expect(done.result.divesImported, 1);

      // The annotation was upserted with the parsed site name + coords.
      expect(ds.annotations, hasLength(1));
      final ann = ds.annotations.values.single;
      expect(ann.siteName, 'Om Sid - Dahab');
      expect(ann.siteLatitude, closeTo(28.420550, 1e-6));
      expect(ann.siteLongitude, closeTo(34.457473, 1e-6));
    });

    test('missing site file → annotation imports without site coords',
        () async {
      final cloneRoot = _tempDir('clones');
      final ds = _FakeBootstrapDataSource();

      // Same dive as above but we deliberately don't copy the Site
      // file. The annotation should still come through (it has buddies
      // / tags / notes etc).
      final repoDir = _bootstrapClone(cloneRoot, 'tester@example.com');
      _copyFixtureDive(repoDir, '2025/05/04-Sun-09=48=36');

      final imp = _makeImporter(
        credentials: _FakeCredentials(),
        cloneRoot: cloneRoot,
        dataSource: ds,
      );

      final events = await imp.import().toList();
      final done = events.last as BootstrapDone;
      expect(done.result.divesImported, 1);

      // 2025/05/04 fixture has buddies / suit / tags so an annotation
      // is still produced — just without site coords because no Site
      // file was on disk.
      final ann = ds.annotations.values.single;
      expect(ann.siteName, isNull);
      expect(ann.siteLatitude, isNull);
      expect(ann.siteLongitude, isNull);
    });

    test('PullConflictException during pull is non-fatal — bootstrap '
        'continues with whatever is on disk', () async {
      final cloneRoot = _tempDir('clones');
      final ds = _FakeBootstrapDataSource();

      final repoDir = _bootstrapClone(cloneRoot, 'tester@example.com');
      _copyFixtureDive(repoDir, '2026/04/04-Sat-13=30=15');

      final imp = _makeImporter(
        credentials: _FakeCredentials(),
        cloneRoot: cloneRoot,
        dataSource: ds,
        pullThrows: PullConflictException('diverged'),
      );

      final events = await imp.import().toList();
      final done = events.last as BootstrapDone;
      expect(done.result.divesImported, 1);
    });
  });

  group('SubsurfaceBootstrapImporter.isPlatformSupported', () {
    test('mirrors SubsurfaceRepo.isPlatformSupported', () {
      final imp = SubsurfaceBootstrapImporter(
        credentials: _FakeCredentials(),
        localCloneRoot: _tempDir('clones'),
        dataSource: _FakeBootstrapDataSource(),
      );
      expect(imp.isPlatformSupported, SubsurfaceRepo.isPlatformSupported);
    });
  });
}
