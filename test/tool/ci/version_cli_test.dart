import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Integration test for tool/ci/version.dart: builds a throwaway git
/// repository, runs the real command line against it and checks stdout, the
/// `$GITHUB_OUTPUT` file and the release notes.
///
/// Repository layout:
///
///     main (= origin/main):  A --- B --- C   (HEAD)
///                             \
///     origin/release/1.1:      D
///
/// Tags: `v1.1.0` (annotated, on A), `v1.1.9` (lightweight, on C), `v1.1.1`
/// (annotated, on D), `v1.0.1` (annotated, on B, but there is no
/// origin/release/1.0), `v0.9.0` (annotated on B, message carries a PGP
/// signature block), `v0.8.0` (annotated on D, so not on main), `v0.7.0`
/// (annotated on B with an empty message), `v0.6.0` (annotated on B, message is
/// only a signature block), `v0.5.0` (annotated on B, message carries an X.509
/// signed-message block). `v1.1.9` stays the highest tag, so nightlies carry
/// 1.2.0.
void main() {
  late Directory tmp;
  late Directory repo;
  late String cli;
  late String shaA;
  late String shaC;
  var runs = 0;

  String git(List<String> args) {
    final r = Process.runSync('git', args, workingDirectory: repo.path);
    if (r.exitCode != 0) {
      fail('git ${args.join(' ')} failed: ${r.stderr}');
    }
    return (r.stdout as String).trim();
  }

  String commit(String subject) {
    git(['commit', '--allow-empty', '-q', '-m', subject]);
    return git(['rev-parse', 'HEAD']);
  }

  setUpAll(() {
    cli = '${Directory.current.path}/tool/ci/version.dart';
    tmp = Directory.systemTemp.createTempSync('version_cli_test_');
    repo = Directory('${tmp.path}/repo')..createSync();

    // Independent of the developer's global git config.
    git(['init', '-q', '-b', 'main']);
    git(['config', 'user.name', 'Test']);
    git(['config', 'user.email', 'test@example.com']);
    git(['config', 'commit.gpgsign', 'false']);
    git(['config', 'tag.gpgsign', 'false']);

    shaA = commit('feat: alpha');
    final shaB = commit('feat: beta');
    shaC = commit('feat: gamma');
    git(['update-ref', 'refs/remotes/origin/main', shaC]);

    git(['tag', '-a', 'v1.1.0', shaA, '-m', 'v1.1.0 — first']);
    git(['tag', 'v1.1.9', shaC]);
    git(['tag', '-a', 'v1.0.1', shaB, '-m', 'v1.0.1 — stray hotfix']);
    git([
      'tag',
      '-a',
      'v0.9.0',
      shaB,
      '-m',
      'v0.9.0 — signed\n\nBody line.\n\n'
          '-----BEGIN PGP SIGNATURE-----\n\nSECRETBLOB\n'
          '-----END PGP SIGNATURE-----',
    ]);
    git(['tag', '-a', 'v0.7.0', shaB, '-m', '']);
    git([
      'tag',
      '-a',
      'v0.6.0',
      shaB,
      '-m',
      '-----BEGIN PGP SIGNATURE-----\n\nONLYBLOB\n-----END PGP SIGNATURE-----',
    ]);
    git([
      'tag',
      '-a',
      'v0.5.0',
      shaB,
      '-m',
      'v0.5.0 — x509\n\nBody line.\n\n'
          '-----BEGIN SIGNED MESSAGE-----\nMIIBLOB\n'
          '-----END SIGNED MESSAGE-----',
    ]);

    git(['checkout', '-q', '-b', 'release-side', shaA]);
    final shaD = commit('fix: hotfix on the release branch');
    git(['update-ref', 'refs/remotes/origin/release/1.1', shaD]);
    git(['tag', '-a', 'v1.1.1', shaD, '-m', 'v1.1.1 — hotfix']);
    git(['tag', '-a', 'v0.8.0', shaD, '-m', 'v0.8.0 — off main']);
    git(['checkout', '-q', 'main']);
    git(['branch', '-q', '-D', 'release-side']);
  });

  tearDownAll(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Runs the CLI in the fixture repository (or in [cwd]). `$GITHUB_OUTPUT`
  /// always points at a file in [tmp] so the test never touches CI's real
  /// output file. Spawned as `dart <file>`, like CI does: `dart run` would
  /// print the package's build-hook progress onto stdout.
  Future<ProcessResult> runCli(
    List<String> args, {
    String? outputFile,
    Directory? cwd,
  }) {
    outputFile ??= '${tmp.path}/output-${runs++}.txt';
    return Process.run(
      'dart',
      [cli, ...args],
      workingDirectory: (cwd ?? repo).path,
      environment: {'GITHUB_OUTPUT': outputFile},
    );
  }

  String notesPath(String name) => '${tmp.path}/$name.txt';

  group('release', () {
    test('push of an annotated tag on main → release outputs', () async {
      final notes = notesPath('release-notes');
      final outputFile = '${tmp.path}/release-output.txt';
      // The CLI appends to $GITHUB_OUTPUT: other steps' lines must survive.
      File(outputFile).writeAsStringSync('other=1\n');
      final r = await runCli([
        '--event', 'push', '--ref', 'refs/tags/v1.1.0', //
        '--run-number', '5', '--base', '100', '--notes-out', notes,
      ], outputFile: outputFile);
      expect(r.exitCode, 0);
      expect(
        r.stdout,
        allOf(
          contains('channel=release'),
          contains('version=1.1.0'),
          contains('build_number=105'),
        ),
      );
      expect(
        File(outputFile).readAsStringSync(),
        'other=1\n'
        'channel=release\n'
        'version=1.1.0\n'
        'build_number=105\n'
        'build=true\n'
        'reason=Release 1.1.0 (build 105) from tag v1.1.0.\n',
      );
      expect(File(notes).readAsStringSync().trim(), 'v1.1.0 — first');
    });

    test('lightweight tag → exit 1 with ::error::', () async {
      final r = await runCli([
        '--event', 'push', '--ref', 'refs/tags/v1.1.9', //
        '--run-number', '6', '--base', '100',
      ]);
      expect(r.exitCode, 1);
      expect(r.stdout, contains('::error::'));
      expect(r.stdout, contains('annotated'));
    });

    test('hotfix tag on origin/release/1.1 → release 1.1.1', () async {
      final r = await runCli([
        '--event', 'push', '--ref', 'refs/tags/v1.1.1', //
        '--run-number', '7', '--base', '100',
      ]);
      expect(r.exitCode, 0);
      expect(r.stdout, contains('channel=release'));
      expect(r.stdout, contains('version=1.1.1'));
      expect(r.stdout, contains('build_number=107'));
    });

    test('x.y.0 tag that is not on main → error', () async {
      final r = await runCli([
        '--event', 'push', '--ref', 'refs/tags/v0.8.0', //
        '--run-number', '8', '--base', '100',
      ]);
      expect(r.exitCode, 1);
      expect(r.stdout, contains('::error::'));
      expect(r.stdout, contains('must be on main'));
    });

    test('hotfix tag without its release branch → error naming it', () async {
      // origin/release/1.0 doesn't exist: a missing ref counts as "not on it".
      final r = await runCli([
        '--event', 'push', '--ref', 'refs/tags/v1.0.1', //
        '--run-number', '8', '--base', '100',
      ]);
      expect(r.exitCode, 1);
      expect(r.stdout, contains('::error::'));
      expect(r.stdout, contains('release/1.0'));
    });

    test('tag that is not in the checkout → error', () async {
      final r = await runCli([
        '--event', 'push', '--ref', 'refs/tags/v1.5.0', //
        '--run-number', '9', '--base', '100',
      ]);
      expect(r.exitCode, 1);
      expect(r.stdout, contains('::error::'));
      expect(r.stdout, contains('v1.5.0'));
    });

    test('already published version → error; empty list is fine', () async {
      final args = [
        '--event', 'push', '--ref', 'refs/tags/v1.1.0', //
        '--run-number', '10', '--base', '100',
      ];
      // Whitespace around the comma-separated versions is trimmed.
      var r = await runCli([...args, '--published', ' 1.0.0 , 1.1.0 ']);
      expect(r.exitCode, 1);
      expect(r.stdout, contains('::error::'));
      expect(r.stdout, contains('already released'));

      r = await runCli([...args, '--published', '']);
      expect(r.exitCode, 0);
      expect(r.stdout, contains('version=1.1.0'));
    });

    test('--published accepts tag names with a leading v', () async {
      // `gh release list --json tagName` reports v1.1.0, not 1.1.0.
      final r = await runCli([
        '--event', 'push', '--ref', 'refs/tags/v1.1.0', //
        '--run-number', '10', '--base', '100', '--published', 'v1.1.0',
      ]);
      expect(r.exitCode, 1);
      expect(r.stdout, contains('::error::'));
      expect(r.stdout, contains('already released'));
    });

    test('release notes drop the signature block', () async {
      final notes = notesPath('signed-notes');
      final r = await runCli([
        '--event', 'push', '--ref', 'refs/tags/v0.9.0', //
        '--run-number', '11', '--base', '100', '--notes-out', notes,
      ]);
      expect(r.exitCode, 0);
      final text = File(notes).readAsStringSync();
      expect(text, contains('v0.9.0 — signed'));
      expect(text, contains('Body line.'));
      expect(text, isNot(contains('SIGNATURE')));
      expect(text, isNot(contains('SECRETBLOB')));
    });

    test('release notes drop an X.509 signed-message block', () async {
      final notes = notesPath('x509-notes');
      final r = await runCli([
        '--event', 'push', '--ref', 'refs/tags/v0.5.0', //
        '--run-number', '11', '--base', '100', '--notes-out', notes,
      ]);
      expect(r.exitCode, 0);
      final text = File(notes).readAsStringSync();
      expect(text, contains('v0.5.0 — x509'));
      expect(text, contains('Body line.'));
      expect(text, isNot(contains('SIGNED MESSAGE')));
      expect(text, isNot(contains('MIIBLOB')));
    });

    test('tag with an empty message → error, nothing written', () async {
      // The notes come from the tag message; the check holds without
      // --notes-out too, and it stops the run before any output.
      final outputFile = '${tmp.path}/empty-message-output.txt';
      final notes = notesPath('empty-message-notes');
      var r = await runCli([
        '--event', 'push', '--ref', 'refs/tags/v0.7.0', //
        '--run-number', '13', '--base', '100',
      ], outputFile: outputFile);
      expect(r.exitCode, 1);
      expect(r.stdout, contains('::error::'));
      expect(r.stdout, contains('no message'));
      expect(r.stdout, contains('v0.7.0'));
      expect(r.stdout, isNot(contains('channel=')));
      expect(
        !File(outputFile).existsSync() ||
            File(outputFile).readAsStringSync().isEmpty,
        isTrue,
      );

      r = await runCli([
        '--event', 'push', '--ref', 'refs/tags/v0.7.0', //
        '--run-number', '13', '--base', '100', '--notes-out', notes,
      ], outputFile: outputFile);
      expect(r.exitCode, 1);
      expect(r.stdout, contains('no message'));
      expect(File(notes).existsSync(), isFalse);
      expect(
        !File(outputFile).existsSync() ||
            File(outputFile).readAsStringSync().isEmpty,
        isTrue,
      );
    });

    test('tag whose message is only a signature → error', () async {
      final r = await runCli([
        '--event', 'push', '--ref', 'refs/tags/v0.6.0', //
        '--run-number', '14', '--base', '100',
        '--notes-out', notesPath('signature-only-notes'),
      ]);
      expect(r.exitCode, 1);
      expect(r.stdout, contains('::error::'));
      expect(r.stdout, contains('no message'));
      expect(File(notesPath('signature-only-notes')).existsSync(), isFalse);
    });

    test('unwritable notes path → ::error:: and exit 1', () async {
      // A directory where the file should go: the write fails.
      final blocked = Directory('${tmp.path}/blocked.txt')..createSync();
      final r = await runCli([
        '--event', 'push', '--ref', 'refs/tags/v1.1.0', //
        '--run-number', '15', '--base', '100', '--notes-out', blocked.path,
      ]);
      expect(r.exitCode, 1);
      expect(r.stdout, contains('::error::'));
      expect(r.stdout, contains('blocked.txt'));
    });

    test('unwritable \$GITHUB_OUTPUT → ::error:: and exit 1', () async {
      final blocked = Directory('${tmp.path}/blocked-output')..createSync();
      final r = await runCli([
        '--event', 'push', '--ref', 'refs/tags/v1.1.0', //
        '--run-number', '16', '--base', '100',
      ], outputFile: blocked.path);
      expect(r.exitCode, 1);
      expect(r.stdout, contains('::error::'));
      expect(r.stdout, contains('blocked-output'));
      expect(r.stdout, isNot(contains('channel=')));
    });

    test('push of a non-tag ref → error', () async {
      final r = await runCli([
        '--event', 'push', '--ref', 'refs/heads/main', //
        '--run-number', '12', '--base', '100',
      ]);
      expect(r.exitCode, 1);
      expect(r.stdout, contains('::error::'));
      expect(r.stdout, contains('refs/heads/main'));
    });
  });

  group('checkout without origin/main', () {
    test('release tag → error that asks for fetch-depth: 0', () async {
      // `git merge-base --is-ancestor` exits 128 for a bad ref; that must not
      // be reported as "the tag is not on main".
      final bare = Directory('${tmp.path}/no-origin')..createSync();
      void bareGit(List<String> args) {
        final r = Process.runSync('git', args, workingDirectory: bare.path);
        if (r.exitCode != 0) {
          fail('git ${args.join(' ')} failed: ${r.stderr}');
        }
      }

      bareGit(['init', '-q', '-b', 'main']);
      bareGit(['config', 'user.name', 'Test']);
      bareGit(['config', 'user.email', 'test@example.com']);
      bareGit(['config', 'commit.gpgsign', 'false']);
      bareGit(['config', 'tag.gpgsign', 'false']);
      bareGit(['commit', '--allow-empty', '-q', '-m', 'feat: only']);
      bareGit(['tag', '-a', 'v1.0.0', '-m', 'v1.0.0 — first']);

      final r = await runCli([
        '--event', 'push', '--ref', 'refs/tags/v1.0.0', //
        '--run-number', '1', '--base', '100',
      ], cwd: bare);
      expect(r.exitCode, 1);
      expect(r.stdout, contains('::error::'));
      expect(r.stdout, contains('origin/main is missing'));
      expect(r.stdout, contains('fetch-depth: 0'));
      expect(r.stdout, isNot(contains('must be on main')));
    });
  });

  group('workflow_dispatch', () {
    test('from a non-main branch → dry-run', () async {
      final notes = notesPath('dry-notes');
      final r = await runCli([
        '--event', 'workflow_dispatch', '--ref', 'refs/heads/feature', //
        '--run-number', '3', '--base', '200', '--notes-out', notes,
      ]);
      expect(r.exitCode, 0);
      expect(r.stdout, contains('channel=dry-run'));
      expect(r.stdout, contains('version=1.2.0'));
      expect(r.stdout, contains('build_number=203'));
      expect(r.stdout, contains('build=true'));
      // No last-delivered SHA: the last commits (at most 20) are the notes.
      expect(
        File(notes).readAsStringSync(),
        'feat: gamma\nfeat: beta\nfeat: alpha\n',
      );
    });

    test('on main with --dry-run → dry-run', () async {
      final r = await runCli([
        '--event', 'workflow_dispatch', '--ref', 'refs/heads/main', //
        '--run-number', '4', '--base', '200', '--dry-run',
      ]);
      expect(r.exitCode, 0);
      expect(r.stdout, contains('channel=dry-run'));
    });

    test('on main → manual nightly that builds', () async {
      final r = await runCli([
        '--event', 'workflow_dispatch', '--ref', 'refs/heads/main', //
        '--run-number', '4', '--base', '200', '--last-delivered-sha', shaC,
      ]);
      expect(r.exitCode, 0);
      expect(r.stdout, contains('channel=nightly'));
      expect(r.stdout, contains('build=true'));
      expect(r.stdout, contains('manual run'));
    });
  });

  group('schedule', () {
    test('with last-delivered == HEAD → build=false', () async {
      final r = await runCli([
        '--event', 'schedule', '--ref', 'refs/heads/main', //
        '--run-number', '20', '--base', '300', '--last-delivered-sha', shaC,
      ]);
      expect(r.exitCode, 0);
      expect(r.stdout, contains('channel=nightly'));
      expect(r.stdout, contains('build=false'));
      expect(r.stdout, contains('Skipped'));
    });

    test(
      'with changes since last delivered → build, notes since then',
      () async {
        final notes = notesPath('nightly-notes');
        final r = await runCli([
          '--event', 'schedule', '--ref', 'refs/heads/main', //
          '--run-number', '21', '--base', '300', '--notes-out', notes,
          '--last-delivered-sha', shaA,
        ]);
        expect(r.exitCode, 0);
        expect(r.stdout, contains('channel=nightly'));
        expect(r.stdout, contains('version=1.2.0'));
        expect(r.stdout, contains('build_number=321'));
        expect(r.stdout, contains('build=true'));
        expect(File(notes).readAsStringSync(), 'feat: gamma\nfeat: beta\n');
      },
    );

    test(
      'unknown last-delivered SHA → notes fall back to recent commits',
      () async {
        final notes = notesPath('fallback-notes');
        final r = await runCli([
          '--event', 'schedule', '--ref', 'refs/heads/main', //
          '--run-number', '22', '--base', '300', '--notes-out', notes,
          '--last-delivered-sha', 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
        ]);
        expect(r.exitCode, 0);
        expect(r.stdout, contains('build=true'));
        expect(
          File(notes).readAsStringSync(),
          'feat: gamma\nfeat: beta\nfeat: alpha\n',
        );
      },
    );
  });

  group('bad invocations', () {
    const valid = [
      '--event', 'schedule', '--ref', 'refs/heads/main', //
      '--run-number', '1', '--base', '1',
    ];

    Future<void> expectError(List<String> args, String mention) async {
      final r = await runCli(args);
      expect(r.exitCode, 1, reason: args.join(' '));
      expect(r.stdout, contains('::error::'), reason: args.join(' '));
      expect(r.stdout, contains(mention), reason: args.join(' '));
    }

    test(
      'missing, malformed and unknown flags → ::error:: and exit 1',
      () async {
        await expectError(['--event', 'schedule'], '--ref');
        await expectError([...valid, '--run-number', 'abc'], '--run-number');
        await expectError([...valid, '--base', '-3'], '--base');
        await expectError(['--event', 'cron', ...valid.skip(2)], 'cron');
        await expectError([...valid, '--bogus', 'x'], '--bogus');
        await expectError([...valid, '--notes-out'], '--notes-out');
        await expectError([...valid, 'stray'], 'stray');
      },
    );
  });
}
