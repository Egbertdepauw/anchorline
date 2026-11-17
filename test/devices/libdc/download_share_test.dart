import 'dart:io';
import 'dart:ui' show Rect;

import 'package:ccrlogger/devices/libdc/download_share.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  late Directory dir;
  late List<({XFile file, String text, Rect? origin})> shared;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('download_share_test');
    shared = [];
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> run(String recording, {int gzipAbove = 10 * 1024 * 1024}) =>
      shareDownload(
        recordingText: recording,
        extraHeader: ['app 1.1.0+48', 'platform macos', 'gatt: 1 service'],
        origin: const Rect.fromLTWH(1, 2, 3, 4),
        now: () => DateTime(2026, 11, 17, 9, 5, 7),
        tempDir: () async => dir,
        // The share-sheet path on every host, Linux CI included; the
        // Linux save-to-Downloads path has its own tests below.
        isLinux: false,
        share: (file, text, origin) async =>
            shared.add((file: file, text: text, origin: origin)),
        gzipAboveBytes: gzipAbove,
      );

  test(
      'the share file has the header, the recording and the log; '
      'large files are gzipped', () async {
    await run('LOG line\nENVELOPE ...\nPACKET ...\n');

    expect(shared, hasLength(1));
    final s = shared.single;
    expect(s.file.name, 'anchorline-download-20261117-090507.txt');
    expect(s.origin, const Rect.fromLTWH(1, 2, 3, 4));
    expect(
        s.text,
        "This file is a recording of your dive computer's download. It "
        'contains the dives on the computer, its serial number and any GPS '
        'positions it logged. Send it to recordings@anchorline.eu or attach '
        'it to an issue at github.com/Egbertdepauw/anchorline/issues so we '
        'can check your computer.');
    final text = File(s.file.path).readAsStringSync();
    expect(text, contains('app 1.1.0+48'));
    expect(text, contains('platform macos'));
    expect(text, contains('gatt: 1 service'));
    expect(text, contains('LOG line\nENVELOPE ...\nPACKET ...\n'));
    expect(
        text.indexOf('gatt: 1 service'), lessThan(text.indexOf('LOG line')));

    // Above the limit the file is gzipped instead, and no plain one written.
    File(s.file.path).deleteSync();
    shared.clear();
    await run('x' * 5000, gzipAbove: 1000);
    final gz = shared.single.file;
    expect(gz.name, 'anchorline-download-20261117-090507.txt.gz');
    final back = String.fromCharCodes(
        gzip.decode(File(gz.path).readAsBytesSync()));
    expect(back, contains('x' * 5000));
    expect(
        File('${dir.path}/anchorline-download-20261117-090507.txt')
            .existsSync(),
        isFalse);
  });

  test('on Linux there is no share sheet: the file is saved to Downloads',
      () async {
    final downloads = Directory('${dir.path}/Downloads')..createSync();
    final path = await shareDownload(
      recordingText: 'LOG line',
      extraHeader: ['app 1'],
      now: () => DateTime(2026, 11, 17, 9, 5, 7),
      tempDir: () async => dir,
      downloadsDir: () async => downloads,
      isLinux: true,
      share: (file, text, origin) async => shared
          .add((file: file, text: text, origin: origin)),
    );
    expect(shared, isEmpty);
    expect(path, '${downloads.path}/anchorline-download-20261117-090507.txt');
    expect(File(path!).readAsStringSync(), contains('LOG line'));
  });

  test('on Linux without a Downloads folder it falls back to the temp dir',
      () async {
    final path = await shareDownload(
      recordingText: 'LOG line',
      extraHeader: const [],
      now: () => DateTime(2026, 11, 17, 9, 5, 7),
      tempDir: () async => dir,
      downloadsDir: () async => null,
      isLinux: true,
    );
    expect(path, startsWith(dir.path));
  });

  test('elsewhere it shares and returns null', () async {
    final path = await shareDownload(
      recordingText: 'x',
      extraHeader: const [],
      tempDir: () async => dir,
      isLinux: false,
      share: (file, text, origin) async => shared
          .add((file: file, text: text, origin: origin)),
    );
    expect(path, isNull);
    expect(shared, hasLength(1));
  });
}
