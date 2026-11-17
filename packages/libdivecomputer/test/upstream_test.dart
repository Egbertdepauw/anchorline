import 'dart:io';

import 'package:libdivecomputer/src/upstream.g.dart';
import 'package:test/test.dart';

/// Reads `UPSTREAM` as a list of `key value...` lines.
List<List<String>> _upstreamLines() => File('UPSTREAM')
    .readAsLinesSync()
    .where((l) => l.trim().isNotEmpty)
    .map((l) => l.trim().split(RegExp(r'\s+')))
    .toList();

String _upstreamValue(String key) =>
    _upstreamLines().singleWhere((l) => l.first == key)[1];

void main() {
  test('UPSTREAM, upstream.g.dart and revision.h name the same commit', () {
    final commit = _upstreamValue('commit');
    expect(commit, matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(kLibdcPinnedCommit, commit);

    final revision = File('native/revision.h').readAsStringSync();
    expect(
      revision.trim(),
      '#define DC_VERSION_REVISION "${commit.substring(0, 7)}"',
    );
  });

  test('every patch file is listed in UPSTREAM and in patches/README.md, '
      'and nothing else is', () {
    final onDisk =
        Directory('patches')
            .listSync()
            .whereType<File>()
            .map((f) => f.uri.pathSegments.last)
            .where((n) => n.endsWith('.patch'))
            .toList()
          ..sort();

    final lines = _upstreamLines();
    final inUpstream =
        lines.where((l) => l.first == 'patch').map((l) => l[1]).toList()
          ..sort();
    if (onDisk.isEmpty) {
      expect(
        lines.where((l) => l.first == 'patches').single,
        ['patches', 'none'],
      );
    } else {
      expect(lines.where((l) => l.first == 'patches'), isEmpty);
    }
    for (final l in lines.where((l) => l.first == 'patch')) {
      // `patch <file name> <upstream status>`: a status is required.
      expect(l.length, greaterThanOrEqualTo(3), reason: l.join(' '));
    }
    expect(inUpstream, onDisk);

    final readme = File('patches/README.md').readAsStringSync();
    final inReadme = RegExp(
      r'`([^`\s]+\.patch)`',
    ).allMatches(readme).map((m) => m.group(1)!).toSet().toList()..sort();
    expect(inReadme, onDisk);
  });

  test('version.h carries the version from the vendored configure.ac', () {
    final configure = File(
      'third_party/libdivecomputer/configure.ac',
    ).readAsStringSync();
    String define(String name) => RegExp(
      'm4_define\\(\\[dc_version_$name\\],\\[([^\\]]*)\\]\\)',
    ).firstMatch(configure)!.group(1)!;
    final major = define('major');
    final minor = define('minor');
    final micro = define('micro');
    final suffix = define('suffix');
    final version = '$major.$minor.$micro${suffix.isEmpty ? '' : '-$suffix'}';

    final header = File(
      'native/include/libdivecomputer/version.h',
    ).readAsStringSync();
    expect(header, contains('#define DC_VERSION "$version"'));
    expect(header, contains('#define DC_VERSION_MAJOR $major\n'));
    expect(header, contains('#define DC_VERSION_MINOR $minor\n'));
    expect(header, contains('#define DC_VERSION_MICRO $micro\n'));
    expect(header, isNot(matches(RegExp(r'@[A-Z_]*@'))));
  });
}
