import 'dart:io';
import 'dart:ui' show Rect;

import 'package:ccrlogger/devices/fit/fit_share.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import '../../_helpers/fit_test_support.dart';

void main() {
  late Directory dir;
  late List<({XFile file, String text, Rect? origin})> shared;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fit_share_test');
    shared = [];
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<String?> run({bool linux = false, Directory? downloads}) {
    final fit = fitFixtureBytes();
    return shareFitDive(
      diveId: 'd1',
      vendor: 'Garmin',
      product: 'Descent Mk3i',
      loadRawBlob: (id) async => id == 'd1' ? fitBlob(fit) : null,
      origin: const Rect.fromLTWH(1, 2, 3, 4),
      now: () => DateTime(2026, 11, 17, 9, 5, 7),
      tempDir: () async => dir,
      downloadsDir: () async => downloads,
      isLinux: linux,
      share: (file, text, origin) async =>
          shared.add((file: file, text: text, origin: origin)),
    );
  }

  test('the shared file is the FIT bytes from the envelope, named by brand '
      'and date', () async {
    final saved = await run();

    expect(saved, isNull);
    expect(shared, hasLength(1));
    final s = shared.single;
    expect(s.file.name, 'garmin-descent-mk3i-20261117-0905.fit');
    expect(File(s.file.path).readAsBytesSync(), fitFixtureBytes());
    // iOS rejects a share without an origin (#232).
    expect(s.origin, const Rect.fromLTWH(1, 2, 3, 4));
    expect(
        s.text,
        "This file is one of your dives, as your watch recorded it. It "
        "contains the dive, the watch's serial number, and any GPS positions "
        'and heart rate it logged. Send it to recordings@anchorline.eu or '
        'attach it to an issue at github.com/Egbertdepauw/anchorline/issues '
        'so we can check your model.');
  });

  test('Linux saves to Downloads and returns the path, with no share sheet',
      () async {
    final downloads = Directory('${dir.path}/Downloads')..createSync();
    final saved = await run(linux: true, downloads: downloads);

    expect(saved, '${downloads.path}/garmin-descent-mk3i-20261117-0905.fit');
    expect(File(saved!).readAsBytesSync(), fitFixtureBytes());
    expect(shared, isEmpty);
  });

  test('Linux without a Downloads folder falls back to the temp dir',
      () async {
    final saved = await run(linux: true);
    expect(saved, startsWith(dir.path));
  });

  test('a dive with no raw blob on this device is an error', () async {
    await expectLater(
      shareFitDive(
        diveId: 'gone',
        vendor: 'Garmin',
        loadRawBlob: (_) async => null,
        tempDir: () async => dir,
        isLinux: false,
        share: (f, t, o) async {},
      ),
      throwsStateError,
    );
  });
}
