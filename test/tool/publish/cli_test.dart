import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// tool/publish/lib is not the package's lib/ folder; the lint matches on the
// path.
// ignore: avoid_relative_lib_imports
import '../../../tool/publish/lib/cli.dart';
// ignore: avoid_relative_lib_imports
import '../../../tool/publish/lib/manifest.dart';
import 'fake_bucket.dart';

const _secretId = 'AKIA-SENTINEL-ID';
const _secretKey = 'sentinel-secret-key-value';

const _env = {
  'DOWNLOADS_BASE_URL': 'https://dl.example',
  'R2_ACCOUNT_ID': 'acct123',
  'R2_BUCKET': 'downloads',
  'AWS_ACCESS_KEY_ID': _secretId,
  'AWS_SECRET_ACCESS_KEY': _secretKey,
};

class _Result {
  _Result(this.code, this.out, this.err);

  final int code;
  final String out;
  final String err;
}

void main() {
  late Directory tmp;
  late String win;
  late String linux;
  late String mac;
  late String notes;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('cli_test_');
    String write(String name, String content) {
      final path = '${tmp.path}/$name';
      File(path).writeAsStringSync(content);
      return path;
    }

    win = write('app.exe', 'windows');
    linux = write('app.AppImage', 'linux');
    mac = write('app.dmg', 'macos');
    notes = write('notes.md', 'Fixes the cell chart.\n\nSecond paragraph.\n');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  /// Runs the command in process against [bucket]; every environment
  /// variable the factory sees is recorded in [factoryEnv].
  Future<_Result> run(
    List<String> args, {
    FakeBucket? bucket,
    Map<String, String> env = _env,
    DateTime? now,
    List<Map<String, String>>? factoryEnv,
  }) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runPublishCli(
      args,
      environment: env,
      bucketFactory: (e) {
        factoryEnv?.add(e);
        return bucket ?? FakeBucket();
      },
      now: () => now ?? DateTime.utc(2026, 11, 3, 8),
      out: out,
      err: err,
    );
    return _Result(code, out.toString(), err.toString());
  }

  /// A failed run: exit code 1 and exactly one `::error::` line on stdout.
  void expectFailure(_Result r, String containing, {FakeBucket? bucket}) {
    expect(r.code, 1, reason: r.out);
    final lines = r.out.trimRight().split('\n');
    expect(lines, hasLength(1), reason: r.out);
    expect(lines.single, startsWith('::error::'));
    expect(lines.single, contains(containing));
    expect(r.out, isNot(contains(_secretKey)));
    expect(r.out, isNot(contains(_secretId)));
    if (bucket != null) expect(bucket.putCalls, isEmpty);
  }

  List<String> release({String version = '1.2.0', List<String>? extra}) => [
    'release',
    '--version',
    version,
    '--build',
    '45',
    '--notes-file',
    notes,
    '--file',
    'windows-x64=$win',
    '--file',
    'linux-x64=$linux',
    ...?extra,
  ];

  List<String> nightly({List<String>? extra}) => [
    'nightly',
    '--version',
    '1.3.0',
    '--build',
    '157',
    '--file',
    'windows-x64=$win',
    '--file',
    'macos=$mac',
    ...?extra,
  ];

  /// A nightly with exactly these files (platform key to path).
  List<String> nightlyOf(Map<String, String> files) => [
    'nightly',
    '--version',
    '1.3.0',
    '--build',
    '157',
    for (final f in files.entries) ...['--file', '${f.key}=${f.value}'],
  ];

  const releasesKey = 'releases/manifest.json';
  const nightlyKey = 'nightly/manifest.json';

  group('release', () {
    test('publishes the files and the notes and says what it did', () async {
      final bucket = FakeBucket();
      final r = await run(release(), bucket: bucket);

      expect(r.code, 0, reason: r.out);
      expect(r.err, isEmpty);
      expect(r.out, contains('release'));
      expect(r.out, contains('1.2.0'));
      expect(r.out, contains('45'));
      expect(
        r.out,
        contains(
          'windows-x64  '
          'https://dl.example/releases/1.2.0/Anchorline-1.2.0-windows-x64.exe',
        ),
      );
      expect(
        r.out,
        contains(
          'https://dl.example/releases/1.2.0/Anchorline-1.2.0-linux-x64.AppImage',
        ),
      );

      final latest = Manifest.parse(bucket.texts[releasesKey]!).latest!;
      expect(latest.version, '1.2.0');
      expect(latest.build, 45);
      expect(latest.notes, 'Fixes the cell chart.\n\nSecond paragraph.');
      expect(latest.date, '2026-11-03');
      expect(latest.files.keys, ['windows-x64', 'linux-x64']);
    });

    test('passes the environment to the bucket factory', () async {
      final seen = <Map<String, String>>[];
      await run(release(), factoryEnv: seen);

      expect(seen.single['R2_ACCOUNT_ID'], 'acct123');
      expect(seen.single['R2_BUCKET'], 'downloads');
    });

    test('says so when a hotfix is listed under previous', () async {
      final bucket = FakeBucket();
      await run(release(), bucket: bucket);
      final r = await run(release(version: '1.1.1'), bucket: bucket);

      expect(r.code, 0, reason: r.out);
      expect(r.out, contains('previous'));
      expect(r.out, contains('1.2.0'));
    });

    test('--force replaces a version that is already published', () async {
      final bucket = FakeBucket();
      await run(release(), bucket: bucket);
      File(win).writeAsStringSync('windows, rebuilt');

      final refused = await run(release(), bucket: bucket);
      expectFailure(refused, '1.2.0');

      final forced = await run(release(extra: ['--force']), bucket: bucket);
      expect(forced.code, 0, reason: forced.out);
      expect(forced.out, contains('Published release 1.2.0'));
      expect(forced.out, isNot(contains('nothing to do')));
    });

    test('publishing the same release again does nothing and says so', () async {
      final bucket = FakeBucket();
      await run(release(), bucket: bucket);
      final written = bucket.texts[releasesKey];
      bucket.calls.clear();

      final r = await run(release(), bucket: bucket);

      expect(r.code, 0, reason: r.out);
      expect(r.out, contains('already published, nothing to do'));
      expect(r.out, contains('1.2.0'));
      expect(
        r.out,
        contains(
          'https://dl.example/releases/1.2.0/Anchorline-1.2.0-windows-x64.exe',
        ),
      );
      expect(r.out, isNot(contains('was updated')));
      expect(r.out, isNot(contains('Published')));
      expect(bucket.calls, ['getText $releasesKey']);
      expect(bucket.texts[releasesKey], written);
    });

    test('--force on the same release again does nothing either', () async {
      final bucket = FakeBucket();
      await run(release(), bucket: bucket);
      bucket.calls.clear();

      final r = await run(release(extra: ['--force']), bucket: bucket);

      expect(r.code, 0, reason: r.out);
      expect(r.out, contains('nothing to do'));
      expect(bucket.putCalls, isEmpty);
    });

    test('a dry run of the same release again says so too', () async {
      final bucket = FakeBucket();
      await run(release(), bucket: bucket);
      bucket.calls.clear();

      final r = await run(release(extra: ['--dry-run']), bucket: bucket);

      expect(r.code, 0, reason: r.out);
      expect(r.out, contains('already published, nothing to do'));
      expect(r.out, isNot(contains('would become')));
      expect(bucket.calls, ['getText $releasesKey']);
    });

    test('the same version with a changed file is refused', () async {
      final bucket = FakeBucket();
      await run(release(), bucket: bucket);
      File(win).writeAsStringSync('windows, rebuilt');
      bucket.calls.clear();

      final r = await run(release(), bucket: bucket);

      expectFailure(r, '1.2.0', bucket: bucket);
    });

    test('a release is for windows-x64 and linux-x64 and no other', () async {
      final bucket = FakeBucket();
      final withMac = await run(
        release(extra: ['--file', 'macos=$mac']),
        bucket: bucket,
      );
      expectFailure(withMac, 'macos', bucket: bucket);
      expect(bucket.calls, isEmpty);

      for (final only in [
        {'windows-x64': win},
        {'linux-x64': linux},
        {'macos': mac},
      ]) {
        final args = [
          'release',
          '--version',
          '1.2.0',
          '--build',
          '45',
          '--notes-file',
          notes,
          for (final f in only.entries) ...['--file', '${f.key}=${f.value}'],
        ];
        final r = await run(args, bucket: bucket);
        expectFailure(r, 'windows-x64 and linux-x64', bucket: bucket);
        expect(bucket.calls, isEmpty);
      }
    });

    test('--dry-run prints the manifest and uploads nothing', () async {
      final bucket = FakeBucket();
      final r = await run(release(extra: ['--dry-run']), bucket: bucket);

      expect(r.code, 0, reason: r.out);
      expect(bucket.putCalls, isEmpty);
      expect(r.out.toLowerCase(), contains('nothing uploaded'));
      expect(r.out, contains('"format": 1'));
      expect(r.out, contains('"version": "1.2.0"'));
      expect(r.out, contains('"sha256"'));
    });

    test('needs a release-notes file', () async {
      final bucket = FakeBucket();
      final args = release().toList()..removeRange(5, 7);
      expectFailure(
        await run(args, bucket: bucket),
        '--notes-file',
        bucket: bucket,
      );
    });

    test('refuses an empty or missing release-notes file', () async {
      final bucket = FakeBucket();
      final empty = '${tmp.path}/empty.md';
      File(empty).writeAsStringSync('  \n\n');
      final args = release().toList();
      final at = args.indexOf('--notes-file') + 1;

      args[at] = empty;
      expectFailure(await run(args, bucket: bucket), 'empty', bucket: bucket);

      args[at] = '${tmp.path}/nope.md';
      expectFailure(await run(args, bucket: bucket), 'nope.md', bucket: bucket);
    });
  });

  group('nightly', () {
    test('publishes to the nightly list; notes are optional', () async {
      final bucket = FakeBucket();
      final r = await run(nightly(), bucket: bucket);

      expect(r.code, 0, reason: r.out);
      expect(r.out, contains('nightly'));
      expect(r.out, contains('1.3.0'));
      expect(r.out, contains('157'));
      expect(bucket.texts.keys, [nightlyKey]);
      final latest = Manifest.parse(bucket.texts[nightlyKey]!).latest!;
      expect(latest.notes, '');
      expect(
        latest.files['macos']!.url,
        'https://dl.example/nightly/1.3.0-157/'
        'Anchorline-Nightly-1.3.0-157-macos.dmg',
      );
    });

    test('takes notes from a notes file when given one', () async {
      final bucket = FakeBucket();
      await run(nightly(extra: ['--notes-file', notes]), bucket: bucket);

      expect(
        Manifest.parse(bucket.texts[nightlyKey]!).latest!.notes,
        startsWith('Fixes the cell chart.'),
      );
    });

    test('a notes file that was given but is missing is an error', () async {
      final bucket = FakeBucket();
      final r = await run(
        nightly(extra: ['--notes-file', '${tmp.path}/nope.md']),
        bucket: bucket,
      );

      expectFailure(r, 'nope.md', bucket: bucket);
    });

    test('--force is only for releases', () async {
      final bucket = FakeBucket();
      final r = await run(nightly(extra: ['--force']), bucket: bucket);

      expectFailure(r, '--force', bucket: bucket);
      expect(bucket.calls, isEmpty);
    });

    test('takes any non-empty set of platforms', () async {
      for (final files in [
        {'macos': mac},
        {'windows-x64': win},
        {'windows-x64': win, 'linux-x64': linux},
      ]) {
        final bucket = FakeBucket();
        final r = await run(nightlyOf(files), bucket: bucket);

        expect(r.code, 0, reason: r.out);
        expect(
          Manifest.parse(bucket.texts[nightlyKey]!).latest!.files.keys,
          files.keys,
        );
      }
    });

    test(
      'publishing the same nightly again does nothing and says so',
      () async {
        final bucket = FakeBucket();
        await run(nightly(), bucket: bucket);
        final written = bucket.texts[nightlyKey];
        bucket.calls.clear();

        final r = await run(nightly(), bucket: bucket);

        expect(r.code, 0, reason: r.out);
        expect(r.out, contains('already published, nothing to do'));
        expect(r.out, contains('157'));
        expect(bucket.calls, ['getText $nightlyKey']);
        expect(bucket.texts[nightlyKey], written);
      },
    );

    test('says so when an older build is listed under previous', () async {
      final bucket = FakeBucket();
      await run(nightly(), bucket: bucket);
      final newer = nightly().toList();
      newer[newer.indexOf('--build') + 1] = '158';
      await run(newer, bucket: bucket);

      final r = await run(nightly(), bucket: bucket);

      expect(r.code, 0, reason: r.out);
      expect(r.out, contains('already published, nothing to do'));
      expect(r.out, contains('build 157 is listed under previous'));
      expect(r.out, contains('latest nightly is build 158'));
    });

    test('the same nightly build with a changed file is refused', () async {
      final bucket = FakeBucket();
      await run(nightly(), bucket: bucket);
      File(mac).writeAsStringSync('macos, rebuilt');
      bucket.calls.clear();

      expectFailure(
        await run(nightly(), bucket: bucket),
        '157',
        bucket: bucket,
      );
    });

    test('--dry-run prints the manifest and uploads nothing', () async {
      final bucket = FakeBucket();
      final r = await run(nightly(extra: ['--dry-run']), bucket: bucket);

      expect(r.code, 0, reason: r.out);
      expect(bucket.putCalls, isEmpty);
      expect(r.out.toLowerCase(), contains('nothing uploaded'));
      expect(r.out, contains('"build": 157'));
    });
  });

  group('rollback', () {
    FakeBucket withReleases() {
      Manifest m = Manifest.empty();
      for (final v in ['1.0.0', '1.1.0', '1.2.0']) {
        m = addRelease(
          m,
          ReleaseEntry(
            version: v,
            build: 1,
            date: '2026-11-01',
            notes: '',
            files: {
              'windows-x64': FileEntry(
                url: 'https://dl.example/$v.exe',
                size: 1,
                sha256: 'ab',
              ),
            },
          ),
        );
      }
      return FakeBucket(texts: {releasesKey: m.encode()});
    }

    // rollback needs the four bucket variables but not DOWNLOADS_BASE_URL.
    final rollbackEnv = {..._env}..remove('DOWNLOADS_BASE_URL');

    test('makes a previous version the latest again', () async {
      final bucket = withReleases();
      final r = await run(
        ['rollback', '--version', '1.1.0'],
        bucket: bucket,
        env: rollbackEnv,
      );

      expect(r.code, 0, reason: r.out);
      expect(r.out, contains('1.1.0'));
      expect(bucket.putCalls, ['putText $releasesKey']);
      expect(
        Manifest.parse(bucket.texts[releasesKey]!).latest!.version,
        '1.1.0',
      );
    });

    test('--dry-run prints the manifest and writes nothing', () async {
      final bucket = withReleases();
      final r = await run(
        ['rollback', '--version', '1.1.0', '--dry-run'],
        bucket: bucket,
        env: rollbackEnv,
      );

      expect(r.code, 0, reason: r.out);
      expect(bucket.putCalls, isEmpty);
      expect(r.out.toLowerCase(), contains('nothing'));
      expect(r.out, contains('"format": 1'));
    });

    test('a version that is not in the list is an error', () async {
      final bucket = withReleases();
      final r = await run(
        ['rollback', '--version', '0.5.0'],
        bucket: bucket,
        env: rollbackEnv,
      );

      expectFailure(r, '0.5.0', bucket: bucket);
    });

    test('needs --version', () async {
      expectFailure(await run(['rollback'], env: rollbackEnv), '--version');
    });

    test('takes no build, notes, files or --force', () async {
      for (final extra in [
        ['--build', '3'],
        ['--notes-file', notes],
        ['--file', 'windows-x64=$win'],
        ['--force'],
      ]) {
        final r = await run([
          'rollback',
          '--version',
          '1.1.0',
          ...extra,
        ], env: rollbackEnv);
        expectFailure(r, extra.first);
      }
    });
  });

  group('arguments', () {
    test('no action', () async {
      final r = await run([]);
      expectFailure(r, 'action');
      expect(r.err, contains('Usage'));
    });

    test('an unknown action', () async {
      final r = await run(['publish', '--version', '1.2.0']);
      expectFailure(r, 'publish');
      expect(r.err, contains('Usage'));
    });

    test('an unknown flag', () async {
      expectFailure(await run(release(extra: ['--bogus', 'x'])), '--bogus');
    });

    test('a flag without its value', () async {
      expectFailure(
        await run(['release', '--version', '--build', '3']),
        '--version',
      );
    });

    test('--version is required', () async {
      final args = release().toList()..removeRange(1, 3);
      expectFailure(await run(args), '--version');
    });

    test(
      'a value flag given twice is refused, not silently overridden',
      () async {
        final bucket = FakeBucket();
        for (final flag in [
          ['--version', '1.9.9'],
          ['--build', '99'],
          ['--notes-file', notes],
        ]) {
          final r = await run(release(extra: flag), bucket: bucket);
          expectFailure(r, flag.first, bucket: bucket);
          expect(r.out, contains('twice'));
        }
      },
    );

    test('--build is required and has to be a positive integer', () async {
      final without = release().toList()..removeRange(3, 5);
      expectFailure(await run(without), '--build');

      for (final bad in ['0', '-3', 'abc', '1.5', '']) {
        final args = release().toList();
        args[args.indexOf('--build') + 1] = bad;
        expectFailure(await run(args), '--build');
      }
    });

    test('at least one --file is required', () async {
      expectFailure(
        await run([
          'release',
          '--version',
          '1.2.0',
          '--build',
          '45',
          '--notes-file',
          notes,
        ]),
        '--file',
      );
    });

    test('--file has to look like key=path, once per key', () async {
      expectFailure(
        await run(release(extra: ['--file', 'windows-x64'])),
        'key=path',
      );
      expectFailure(await run(release(extra: ['--file', '=$win'])), 'key=path');
      expectFailure(
        await run(release(extra: ['--file', 'windows-x64=$win'])),
        'windows-x64',
      );
    });

    test('a --file path that does not exist', () async {
      final bucket = FakeBucket();
      final r = await run(
        nightlyOf({'macos': '${tmp.path}/ghost.dmg'}),
        bucket: bucket,
      );

      expectFailure(r, 'ghost.dmg', bucket: bucket);
      expect(bucket.calls, isEmpty);
    });

    test('a platform or extension that is not supported', () async {
      final bucket = FakeBucket();
      expectFailure(
        await run(release(extra: ['--file', 'freebsd=$win']), bucket: bucket),
        'freebsd',
        bucket: bucket,
      );
      final zip = '${tmp.path}/app.zip';
      File(zip).writeAsStringSync('zip');
      expectFailure(
        await run(nightlyOf({'macos': zip}), bucket: bucket),
        '.zip',
        bucket: bucket,
      );
    });

    test('a version that is not X.Y.Z', () async {
      final args = release().toList();
      args[args.indexOf('--version') + 1] = '1.2';
      final bucket = FakeBucket();

      expectFailure(await run(args, bucket: bucket), '1.2', bucket: bucket);
    });
  });

  group('environment', () {
    test('missing variables are listed by name in one error', () async {
      final bucket = FakeBucket();
      final env = {..._env}
        ..remove('R2_BUCKET')
        ..remove('DOWNLOADS_BASE_URL')
        ..['AWS_ACCESS_KEY_ID'] = '  ';
      final r = await run(release(), bucket: bucket, env: env);

      expectFailure(r, 'R2_BUCKET', bucket: bucket);
      expect(r.out, contains('DOWNLOADS_BASE_URL'));
      expect(r.out, contains('AWS_ACCESS_KEY_ID'));
      expect(r.out, isNot(contains('R2_ACCOUNT_ID')));
      expect(r.out, isNot(contains('AWS_SECRET_ACCESS_KEY')));
      expect(bucket.calls, isEmpty);
    });

    test('a dry run still needs the bucket variables', () async {
      final env = {..._env}..remove('AWS_SECRET_ACCESS_KEY');
      final r = await run(release(extra: ['--dry-run']), env: env);

      expectFailure(r, 'AWS_SECRET_ACCESS_KEY');
    });

    test('DOWNLOADS_BASE_URL has to be an https URL', () async {
      for (final bad in [
        'dl.example/files',
        'http://dl.example',
        'ftp://dl.example',
        'https://',
      ]) {
        final bucket = FakeBucket();
        final r = await run(
          release(),
          bucket: bucket,
          env: {..._env, 'DOWNLOADS_BASE_URL': bad},
        );

        expectFailure(r, 'DOWNLOADS_BASE_URL', bucket: bucket);
        expect(r.out, contains('https'), reason: bad);
        expect(bucket.calls, isEmpty);
      }
    });

    test(
      'an https URL, with a path or a trailing slash, is accepted',
      () async {
        for (final good in [
          'https://dl.example',
          'https://dl.example/files/',
        ]) {
          final r = await run(
            release(),
            env: {..._env, 'DOWNLOADS_BASE_URL': good},
          );

          expect(r.code, 0, reason: '$good: ${r.out}');
        }
      },
    );
  });

  group('failures from the publisher and the bucket', () {
    test('a multi-line bucket error becomes one ::error:: line', () async {
      final bucket = _FailingBucket(
        const PublishError('uploading k failed:\nAccess Denied\n  (403)'),
      );
      final out = StringBuffer();
      final code = await runPublishCli(
        release(),
        environment: _env,
        bucketFactory: (_) => bucket,
        now: () => DateTime.utc(2026, 11, 3),
        out: out,
        err: StringBuffer(),
      );

      expect(code, 1);
      expect(
        out.toString(),
        '::error::uploading k failed: Access Denied (403)\n',
      );
    });
  });
}

/// A bucket whose every read fails the way aws would.
class _FailingBucket extends FakeBucket {
  _FailingBucket(this.error);

  final PublishError error;

  @override
  Future<String?> getText(String key) => Future.error(error);
}
