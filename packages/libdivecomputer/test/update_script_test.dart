import 'dart:io';

import 'package:test/test.dart';

/// Runs tool/update_upstream.sh against a tiny local upstream, to pin down
/// that patches are applied (and that a stale one fails) wherever the package
/// lives, including inside another git repository.
void main() {
  late Directory tmp;
  late String commit;
  late String upstreamUrl;

  ProcessResult git(String dir, List<String> args) {
    final r = Process.runSync('git', [
      '-C',
      dir,
      '-c',
      'user.name=t',
      '-c',
      'user.email=t@example.com',
      ...args,
    ]);
    if (r.exitCode != 0) fail('git $args: ${r.stderr}');
    return r;
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('libdc_script_test');
    final up = '${tmp.path}/upstream';
    for (final f in {
      'include/libdivecomputer/version.h.in':
          '#define DC_VERSION "@DC_VERSION@"\n'
          '#define DC_VERSION_MAJOR @DC_VERSION_MAJOR@\n'
          '#define DC_VERSION_MINOR @DC_VERSION_MINOR@\n'
          '#define DC_VERSION_MICRO @DC_VERSION_MICRO@\n',
      'src/a.c': 'int a;\n',
      'src/a.h': 'int a;\n',
      'src/libdivecomputer.symbols': 'a\n',
      'COPYING': 'c\n',
      'NEWS': 'news\n',
      'README': 'r\n',
      'configure.ac':
          'm4_define([dc_version_major],[1])\n'
          'm4_define([dc_version_minor],[2])\n'
          'm4_define([dc_version_micro],[3])\n'
          'm4_define([dc_version_suffix],[])\n',
      'contrib/android/Android.mk': 'x\n',
      'contrib/msvc/libdivecomputer.vcxproj': 'x\n',
    }.entries) {
      File('$up/${f.key}')
        ..createSync(recursive: true)
        ..writeAsStringSync(f.value);
    }
    git(up, ['init', '-q']);
    git(up, ['add', '.']);
    git(up, ['commit', '-q', '-m', 'init']);
    commit = (git(up, ['rev-parse', 'HEAD']).stdout as String).trim();
    upstreamUrl = 'file://$up';

    final pkg = '${tmp.path}/pkg';
    Directory('$pkg/patches').createSync(recursive: true);
    Directory('$pkg/tool').createSync();
    for (final s in ['update_upstream.sh', 'check_vendor.sh']) {
      File('tool/$s').copySync('$pkg/tool/$s');
    }
    File('$pkg/UPSTREAM').writeAsStringSync('commit $commit\npatches none\n');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  ProcessResult run() => Process.runSync(
    'bash',
    ['${tmp.path}/pkg/tool/update_upstream.sh', commit],
    environment: {'LIBDC_UPSTREAM_URL': upstreamUrl},
  );

  const patch =
      '--- a/NEWS\n+++ b/NEWS\n@@ -1 +1,2 @@\n news\n+patched\n';

  test('a listed patch is applied, rooted at the upstream repository', () {
    File('${tmp.path}/pkg/patches/0001-news.patch').writeAsStringSync(patch);
    File('${tmp.path}/pkg/UPSTREAM').writeAsStringSync(
      'commit $commit\npatch 0001-news.patch submitted\n',
    );
    final r = run();
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(
      File('${tmp.path}/pkg/third_party/libdivecomputer/NEWS')
          .readAsStringSync(),
      'news\npatched\n',
    );
    expect(
      File('${tmp.path}/pkg/native/include/libdivecomputer/version.h')
          .readAsStringSync(),
      contains('#define DC_VERSION "1.2.3"'),
    );
  });

  test('a patch that no longer applies fails with the documented message', () {
    File('${tmp.path}/pkg/patches/0001-news.patch').writeAsStringSync(
      patch.replaceFirst(' news\n', ' other\n'),
    );
    File('${tmp.path}/pkg/UPSTREAM').writeAsStringSync(
      'commit $commit\npatch 0001-news.patch submitted\n',
    );
    final r = run();
    expect(r.exitCode, 1);
    expect(
      r.stderr,
      contains(
        'patch 0001-news.patch no longer applies: if upstream merged it, '
        'delete it in this PR',
      ),
    );
  });

  test('a patch without an UPSTREAM line is refused', () {
    File('${tmp.path}/pkg/patches/0001-news.patch').writeAsStringSync(patch);
    final r = run();
    expect(r.exitCode, 1);
    expect(r.stderr, contains('has no'));
  });
}
