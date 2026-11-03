import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import '_helpers/strict_golden_comparator.dart';

/// A 4 x 4 white image with one black pixel at ([blackX], 0).
Future<ui.Image> _image({required int blackX}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
    ..drawRect(
      const ui.Rect.fromLTWH(0, 0, 4, 4),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    )
    ..drawRect(
      ui.Rect.fromLTWH(blackX.toDouble(), 0, 1, 1),
      ui.Paint()..color = const ui.Color(0xFF000000),
    );
  final picture = recorder.endRecording();
  final image = await picture.toImage(4, 4);
  picture.dispose();
  return image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('flutter_test_config.dart installs the strict comparator', () {
    expect(goldenFileComparator, isA<StrictLocalFileComparator>());
  });

  // The cylinder label goldens compare a ui.Image in a plain test(), where
  // the stock comparator's mismatch is swallowed (see the comparator's doc).
  group('a ui.Image golden in a plain test()', () {
    late Directory dir;
    late GoldenFileComparator installed;
    late bool updating;
    late ui.Image golden;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('strict_golden_');
      installed = goldenFileComparator;
      updating = autoUpdateGoldenFiles;
      // Under --update-goldens the matcher would rewrite guard.png instead
      // of comparing against it.
      autoUpdateGoldenFiles = false;
      goldenFileComparator =
          StrictLocalFileComparator(dir.uri.resolve('guard_test.dart'));
      golden = await _image(blackX: 0);
      final png = await golden.toByteData(format: ui.ImageByteFormat.png);
      await goldenFileComparator.update(
        Uri.parse('guard.png'),
        png!.buffer.asUint8List(),
      );
    });

    tearDown(() async {
      goldenFileComparator = installed;
      autoUpdateGoldenFiles = updating;
      golden.dispose();
      await dir.delete(recursive: true);
    });

    test('matches an identical image', () async {
      await expectLater(golden, matchesGoldenFile('guard.png'));
    });

    test('fails an image that is one pixel off', () async {
      final moved = await _image(blackX: 1);
      addTearDown(moved.dispose);
      final mismatch = await matchesGoldenFile('guard.png').matchAsync(moved);
      expect(mismatch, contains('Pixel test failed'));
    });
  });
}
