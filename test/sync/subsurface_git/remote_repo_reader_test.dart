// Tests for readRemoteRepoFiles — the app-side directory walk that feeds
// RemoteSnapshot.fromFiles.

@TestOn('mac-os || linux || windows')
library;

import 'dart:io';

import 'package:ccrlogger/sync/subsurface_git/remote_repo_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ccrlog_reader_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('reads every file keyed by POSIX relative path and skips .git',
      () async {
    File(p.join(tmp.path, '00-Subsurface')).writeAsStringSync('version 3\n');
    File(p.join(tmp.path, '2026', '04', '04-Sat-13=30=15', 'Dive-705'))
      ..createSync(recursive: true)
      ..writeAsStringSync('duration 57:30 min\n');
    File(p.join(tmp.path, '.git', 'HEAD'))
      ..createSync(recursive: true)
      ..writeAsStringSync('ref: refs/heads/x\n');
    final files = await readRemoteRepoFiles(tmp);
    expect(files.keys.toSet(),
        {'00-Subsurface', '2026/04/04-Sat-13=30=15/Dive-705'});
    expect(files['2026/04/04-Sat-13=30=15/Dive-705'], 'duration 57:30 min\n');
  });

  test('missing root gives an empty map', () async {
    expect(await readRemoteRepoFiles(Directory('${tmp.path}/nope')), isEmpty);
  });

  test('a file that is not valid UTF-8 is skipped', () async {
    File(p.join(tmp.path, 'ok')).writeAsStringSync('x\n');
    File(p.join(tmp.path, 'bad')).writeAsBytesSync([0xff, 0xfe, 0x00, 0xc3]);
    final files = await readRemoteRepoFiles(tmp);
    expect(files.keys, ['ok']);
  });
}
