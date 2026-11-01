import 'dart:typed_data';

import 'package:ccrlogger/label_printer/label_bitmap.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds an RGBA buffer of [width] x [height] opaque white pixels.
Uint8List _whiteRgba(int width, int height) =>
    Uint8List(width * height * 4)..fillRange(0, width * height * 4, 255);

void _setPixel(
  Uint8List rgba,
  int width,
  int x,
  int y,
  int r,
  int g,
  int b,
  int a,
) {
  final i = (y * width + x) * 4;
  rgba[i] = r;
  rgba[i + 1] = g;
  rgba[i + 2] = b;
  rgba[i + 3] = a;
}

void main() {
  test('label geometry constants match 50 x 30 mm at 203 dpi', () {
    expect(kLabelWidthDots, 384);
    expect(kLabelHeightDots, 240);
    expect(kLabelSafeMarginDots, 12);
  });

  group('LabelBitmap.blank', () {
    test('384 x 240 has 48 bytes per row, 11520 bytes, all white', () {
      final b = LabelBitmap.blank(384, 240);
      expect(b.width, 384);
      expect(b.height, 240);
      expect(b.bytesPerRow, 48);
      expect(b.bits.length, 11520);
      expect(b.bits.every((byte) => byte == 0), isTrue);
      expect(b.isBlack(0, 0), isFalse);
      expect(b.isBlack(383, 239), isFalse);
    });

    test('rounds bytes per row up for widths that are not a multiple of 8', () {
      expect(LabelBitmap.blank(9, 2).bytesPerRow, 2);
      expect(LabelBitmap.blank(9, 2).bits.length, 4);
      expect(LabelBitmap.blank(8, 1).bytesPerRow, 1);
    });
  });

  group('LabelBitmap.isBlack', () {
    test('reads bits MSB first', () {
      final bits = Uint8List.fromList([0x80, 0x01]);
      final b = LabelBitmap(width: 16, height: 1, bits: bits);
      expect(b.isBlack(0, 0), isTrue);
      expect(b.isBlack(1, 0), isFalse);
      expect(b.isBlack(7, 0), isFalse);
      expect(b.isBlack(8, 0), isFalse);
      expect(b.isBlack(15, 0), isTrue);
    });

    test('rejects coordinates outside the bitmap', () {
      final b = LabelBitmap.blank(9, 2);
      expect(() => b.isBlack(-1, 0), throwsRangeError);
      expect(() => b.isBlack(9, 0), throwsRangeError);
      expect(() => b.isBlack(0, -1), throwsRangeError);
      expect(() => b.isBlack(0, 2), throwsRangeError);
    });
  });

  test('constructor rejects a bit buffer of the wrong length', () {
    expect(
      () => LabelBitmap(width: 9, height: 2, bits: Uint8List(3)),
      throwsArgumentError,
    );
  });

  group('bitmapFromRgba', () {
    test('9 x 2: black at (0,0) and (8,1) set bit 7 of bytes 0 and 3', () {
      final rgba = _whiteRgba(9, 2);
      _setPixel(rgba, 9, 0, 0, 0, 0, 0, 255);
      _setPixel(rgba, 9, 8, 1, 0, 0, 0, 255);

      final b = bitmapFromRgba(rgba, 9, 2);

      expect(b.width, 9);
      expect(b.height, 2);
      expect(b.bytesPerRow, 2);
      expect(b.bits, [0x80, 0x00, 0x00, 0x80]);
      expect(b.isBlack(0, 0), isTrue);
      expect(b.isBlack(8, 1), isTrue);
      expect(b.isBlack(1, 0), isFalse);
      expect(b.isBlack(8, 0), isFalse);
    });

    test('packs a full row MSB first', () {
      final rgba = _whiteRgba(8, 1);
      // Pixels 0, 2 and 7 black -> 1010 0001.
      for (final x in [0, 2, 7]) {
        _setPixel(rgba, 8, x, 0, 0, 0, 0, 255);
      }
      expect(bitmapFromRgba(rgba, 8, 1).bits, [0xA1]);
    });

    test('mid-grey 127 is black, 128 is white (default threshold 128)', () {
      final rgba = _whiteRgba(2, 1);
      _setPixel(rgba, 2, 0, 0, 127, 127, 127, 255);
      _setPixel(rgba, 2, 1, 0, 128, 128, 128, 255);

      final b = bitmapFromRgba(rgba, 2, 1);

      expect(b.isBlack(0, 0), isTrue);
      expect(b.isBlack(1, 0), isFalse);
    });

    test('weights the channels by (299 R + 587 G + 114 B) / 1000', () {
      final rgba = _whiteRgba(3, 1);
      // Pure green: 587 / 1000 * 255 = 149.7, white.
      _setPixel(rgba, 3, 0, 0, 0, 255, 0, 255);
      // Pure blue: 114 / 1000 * 255 = 29.1, black.
      _setPixel(rgba, 3, 1, 0, 0, 0, 255, 255);
      // Pure red: 299 / 1000 * 255 = 76.2, black.
      _setPixel(rgba, 3, 2, 0, 255, 0, 0, 255);

      final b = bitmapFromRgba(rgba, 3, 1);

      expect(b.isBlack(0, 0), isFalse);
      expect(b.isBlack(1, 0), isTrue);
      expect(b.isBlack(2, 0), isTrue);
    });

    test('a custom threshold moves the black/white boundary', () {
      final rgba = _whiteRgba(1, 1);
      _setPixel(rgba, 1, 0, 0, 100, 100, 100, 255);
      expect(bitmapFromRgba(rgba, 1, 1, threshold: 100).isBlack(0, 0), isFalse);
      expect(bitmapFromRgba(rgba, 1, 1, threshold: 101).isBlack(0, 0), isTrue);
    });

    test('alpha 0 is white even when the colour is black', () {
      final rgba = _whiteRgba(2, 1);
      _setPixel(rgba, 2, 0, 0, 0, 0, 0, 0);
      _setPixel(rgba, 2, 1, 0, 0, 0, 0, 255);

      final b = bitmapFromRgba(rgba, 2, 1);

      expect(b.isBlack(0, 0), isFalse);
      expect(b.isBlack(1, 0), isTrue);
    });

    test('rejects a buffer that is not width * height * 4 bytes', () {
      expect(() => bitmapFromRgba(Uint8List(7), 2, 1), throwsArgumentError);
    });
  });
}
