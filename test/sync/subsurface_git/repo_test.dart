// Integration-style tests for SubsurfaceRepo against local file:// repos.
//
// These exercise the full git2dart wrapper without going to the network.
// Each test sets up a temporary "remote" — typically a bare repo built
// via `git init --bare` plus a worktree we use to seed an initial
// commit — and then drives the wrapper's clone / pull / commit / push
// against `file://...` URLs.
//
// Tests are sequential by design: every `Directory.systemTemp.createTempSync`
// goes through `addTearDown` so we don't leave temp files lying around
// even when a test fails mid-flight.

@TestOn('mac-os || linux || windows')
library;

import 'dart:io';

import 'package:ccrlogger/sync/subsurface_git/credentials.dart';
import 'package:ccrlogger/sync/subsurface_git/repo.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal in-memory credentials source for tests. We don't use real
/// auth (file:// transport ignores credentials) but we still want to
/// verify that the repo wrapper *consults* the credentials source on
/// every network op — the orchestrator relies on that to pick up
/// rotated passwords without rebuilding the repo handle.
class _FakeCredentials implements SubsurfaceCredentialsSource {
  _FakeCredentials();
  final String email = 'tester@example.com';
  final String password = 'pw';
  int reads = 0;

  @override
  Future<({String email, String password})?> read() async {
    reads++;
    return (email: email, password: password);
  }

  @override
  Future<void> save(String email, String password) async => throw UnimplementedError();

  @override
  Future<void> clear() async => throw UnimplementedError();
}

/// Run a `git` subprocess in [cwd]. Throws on non-zero exit so
/// fixture-setup failures are loud.
ProcessResult _git(String cwd, List<String> args) {
  final r = Process.runSync('git', args, workingDirectory: cwd);
  if (r.exitCode != 0) {
    throw StateError(
      'git ${args.join(' ')} in $cwd failed: ${r.stderr}\n${r.stdout}',
    );
  }
  return r;
}

/// Build a temp dir, register cleanup, and return it.
Directory _tempDir(String prefix) {
  final dir = Directory.systemTemp.createTempSync('ccrlog_$prefix');
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return dir;
}

/// Builds an "upstream" bare repo with one initial commit on the
/// branch named [branch], and returns its `file://` URL.
String _seedBareRemote({required String branch}) {
  final bare = _tempDir('bare');
  _git(bare.path, ['init', '--bare', '--initial-branch=$branch']);

  // Stage + commit through a temporary working clone, then push to the
  // bare. We can't commit directly into a bare repo via the CLI.
  final seed = _tempDir('seed');
  _git(seed.path, ['init', '--initial-branch=$branch']);
  _git(seed.path, ['config', 'user.email', 'seed@example.com']);
  _git(seed.path, ['config', 'user.name', 'seed']);
  File('${seed.path}/README').writeAsStringSync('initial\n');
  _git(seed.path, ['add', 'README']);
  _git(seed.path, ['commit', '-m', 'seed']);
  _git(seed.path, ['remote', 'add', 'origin', 'file://${bare.path}']);
  _git(seed.path, ['push', 'origin', branch]);

  return 'file://${bare.path}';
}

void main() {
  group('static API', () {
    test('urlForEmail builds the eu Subsurface Cloud URL', () {
      expect(
        SubsurfaceRepo.urlForEmail('foo@bar.com'),
        'https://ssrf-cloud-eu.subsurface-divelog.org/git/foo@bar.com',
      );
    });

    test('isPlatformSupported is true on this host (macOS)', () {
      // The test host runs macOS — git2dart_binaries ships a macOS
      // dylib, so the wrapper must consider this platform supported.
      expect(SubsurfaceRepo.isPlatformSupported, isTrue);
      expect(Platform.isIOS, isFalse);
    });
  });

  group('against a local bare remote', () {
    const branch = 'tester@example.com';

    test('ensureCloned clones once and is a no-op the second time',
        () async {
      final remoteUrl = _seedBareRemote(branch: branch);
      final localDir = _tempDir('local');
      final creds = _FakeCredentials();
      final repo = SubsurfaceRepo(
        localDir: localDir,
        remoteUrl: remoteUrl,
        credentials: creds,
      );

      await repo.ensureCloned();
      expect(Directory('${localDir.path}/.git').existsSync(), isTrue);
      expect(File('${localDir.path}/README').existsSync(), isTrue);
      final firstReadCount = creds.reads;

      // Second call: the wrapper sees `.git` already exists and does
      // nothing — credentials shouldn't be touched.
      await repo.ensureCloned();
      expect(creds.reads, firstReadCount);
    });

    test('currentBranch reflects the cloned branch', () async {
      final remoteUrl = _seedBareRemote(branch: branch);
      final localDir = _tempDir('local');
      final repo = SubsurfaceRepo(
        localDir: localDir,
        remoteUrl: remoteUrl,
        credentials: _FakeCredentials(),
      );
      await repo.ensureCloned();
      expect(repo.currentBranch, branch);
    });

    test('pull fast-forwards from the remote', () async {
      final remoteUrl = _seedBareRemote(branch: branch);
      final localDir = _tempDir('local');
      final creds = _FakeCredentials();
      final repo = SubsurfaceRepo(
        localDir: localDir,
        remoteUrl: remoteUrl,
        credentials: creds,
      );
      await repo.ensureCloned();
      final readsBefore = creds.reads;

      // Push a new commit into the bare repo from a third clone, so
      // our local is one commit behind.
      final pusher = _tempDir('pusher');
      // Strip the file:// prefix to get a path git can clone from.
      final barePath = remoteUrl.replaceFirst('file://', '');
      _git(pusher.path, ['clone', '-b', branch, barePath, '.']);
      _git(pusher.path, ['config', 'user.email', 'pusher@example.com']);
      _git(pusher.path, ['config', 'user.name', 'pusher']);
      File('${pusher.path}/upstream-change').writeAsStringSync('hi\n');
      _git(pusher.path, ['add', 'upstream-change']);
      _git(pusher.path, ['commit', '-m', 'upstream change']);
      _git(pusher.path, ['push', 'origin', branch]);

      await repo.pull();
      // The remote's new file should now exist locally.
      expect(File('${localDir.path}/upstream-change').existsSync(), isTrue);
      // Auth was consulted.
      expect(creds.reads, greaterThan(readsBefore));
    });

    test('pull is a no-op when already up to date', () async {
      final remoteUrl = _seedBareRemote(branch: branch);
      final localDir = _tempDir('local');
      final repo = SubsurfaceRepo(
        localDir: localDir,
        remoteUrl: remoteUrl,
        credentials: _FakeCredentials(),
      );
      await repo.ensureCloned();
      // Should complete without throwing.
      await repo.pull();
    });

    test('stageAll + commit produces a SHA, second commit returns null',
        () async {
      final remoteUrl = _seedBareRemote(branch: branch);
      final localDir = _tempDir('local');
      final repo = SubsurfaceRepo(
        localDir: localDir,
        remoteUrl: remoteUrl,
        credentials: _FakeCredentials(),
      );
      await repo.ensureCloned();

      File('${localDir.path}/new-file.txt').writeAsStringSync('hello\n');
      await repo.stageAll();
      final sha1 = await repo.commit('add new-file');
      expect(sha1, isNotNull);
      expect(sha1!.length, 40);

      // No further changes — second commit should return null.
      await repo.stageAll();
      final sha2 = await repo.commit('nothing-to-commit');
      expect(sha2, isNull);
    });

    test('stageAll picks up deletions', () async {
      final remoteUrl = _seedBareRemote(branch: branch);
      final localDir = _tempDir('local');
      final repo = SubsurfaceRepo(
        localDir: localDir,
        remoteUrl: remoteUrl,
        credentials: _FakeCredentials(),
      );
      await repo.ensureCloned();
      // Delete the seed file. `git add -A` (stageAll) must record
      // the deletion so the next commit removes it.
      File('${localDir.path}/README').deleteSync();
      await repo.stageAll();
      final sha = await repo.commit('drop README');
      expect(sha, isNotNull);
      // Verify the tree no longer has README.
      final lsTree = _git(localDir.path, ['ls-tree', '-r', 'HEAD']);
      expect(lsTree.stdout.toString(), isNot(contains('README')));
    });

    test('commit uses configured author identity', () async {
      final remoteUrl = _seedBareRemote(branch: branch);
      final localDir = _tempDir('local');
      final repo = SubsurfaceRepo(
        localDir: localDir,
        remoteUrl: remoteUrl,
        credentials: _FakeCredentials(),
        authorName: 'CCRLog Test',
        authorEmail: 'ccrlog-test@example.com',
      );
      await repo.ensureCloned();
      File('${localDir.path}/x').writeAsStringSync('y');
      await repo.stageAll();
      final sha = await repo.commit('hi');
      expect(sha, isNotNull);
      final show = _git(localDir.path, ['log', '-1', '--format=%an <%ae>']);
      expect(
        show.stdout.toString().trim(),
        'CCRLog Test <ccrlog-test@example.com>',
      );
    });

    test('push round-trips a commit to the bare remote', () async {
      final remoteUrl = _seedBareRemote(branch: branch);
      final localDir = _tempDir('local');
      final creds = _FakeCredentials();
      final repo = SubsurfaceRepo(
        localDir: localDir,
        remoteUrl: remoteUrl,
        credentials: creds,
      );
      await repo.ensureCloned();
      File('${localDir.path}/pushable').writeAsStringSync('payload\n');
      await repo.stageAll();
      final sha = await repo.commit('add pushable');
      expect(sha, isNotNull);

      final readsBefore = creds.reads;
      await repo.push();
      expect(creds.reads, greaterThan(readsBefore),
          reason: 'push must consult credentials');

      // Verify the bare repo now contains our commit.
      final barePath = remoteUrl.replaceFirst('file://', '');
      final logOut = _git(barePath, ['log', branch, '--format=%H %s']);
      expect(logOut.stdout.toString(), contains('add pushable'));
    });

    test('throws GitAuthException when no credentials are saved', () async {
      final remoteUrl = _seedBareRemote(branch: branch);
      final localDir = _tempDir('local');
      final repo = SubsurfaceRepo(
        localDir: localDir,
        remoteUrl: remoteUrl,
        credentials: _EmptyCredentials(),
      );
      await expectLater(
        repo.ensureCloned(),
        throwsA(isA<GitAuthException>()),
      );
    });
  });
}

/// Always-empty credentials — used to assert that the wrapper raises
/// GitAuthException rather than handing libgit2 nulls.
class _EmptyCredentials implements SubsurfaceCredentialsSource {
  @override
  Future<({String email, String password})?> read() async => null;
  @override
  Future<void> save(String email, String password) async =>
      throw UnimplementedError();
  @override
  Future<void> clear() async => throw UnimplementedError();
}
