/// The 1-bit bitmap a label printer prints (issue #114).
///
/// Pure Dart, no Flutter imports. The renderer draws a label, converts it
/// with [bitmapFromRgba], and a printer encoder packs the [LabelBitmap]
/// into its own command bytes.
library;

import 'dart:typed_data';

/// Label width in dots: 50 mm at 203 dpi, the Phomemo M110's 48-byte row.
const int kLabelWidthDots = 384;

/// Label height in dots: 30 mm at 203 dpi.
const int kLabelHeightDots = 240;

/// All label content stays inside this margin (1.5 mm), because the print
/// head cannot reach the label edge reliably.
const int kLabelSafeMarginDots = 12;

/// A 1-bit raster. Rows are packed MSB first: pixel `x` of a row is bit
/// `7 - (x % 8)` of byte `x ~/ 8`, and 1 means black. Each row starts on a
/// byte boundary, so a row is [bytesPerRow] bytes and the last byte is
/// zero-padded when [width] is not a multiple of 8.
class LabelBitmap {
  LabelBitmap({required this.width, required this.height, required this.bits}) {
    if (bits.length != bytesPerRow * height) {
      throw ArgumentError(
        'A $width x $height bitmap needs ${bytesPerRow * height} bytes, '
        'got ${bits.length}',
      );
    }
  }

  /// An all-white bitmap.
  factory LabelBitmap.blank(int width, int height) => LabelBitmap(
    width: width,
    height: height,
    bits: Uint8List(((width + 7) ~/ 8) * height),
  );

  final int width;
  final int height;

  /// Packed rows, [bytesPerRow] bytes each, [height] rows.
  final Uint8List bits;

  int get bytesPerRow => (width + 7) ~/ 8;

  /// Whether the pixel at ([x], [y]) is black.
  bool isBlack(int x, int y) {
    RangeError.checkValueInInterval(x, 0, width - 1, 'x');
    RangeError.checkValueInInterval(y, 0, height - 1, 'y');
    return bits[y * bytesPerRow + (x >> 3)] & (0x80 >> (x & 7)) != 0;
  }
}

/// Thresholds a straight (non-premultiplied) RGBA buffer into a bitmap.
///
/// A pixel is black when its luminance `(299 R + 587 G + 114 B) / 1000` is
/// below [threshold]. A fully transparent pixel (alpha 0) is white whatever
/// its colour; any other alpha is not blended, because the renderer draws
/// on an opaque white background.
LabelBitmap bitmapFromRgba(
  Uint8List rgba,
  int width,
  int height, {
  int threshold = 128,
}) {
  if (rgba.length != width * height * 4) {
    throw ArgumentError(
      'A $width x $height RGBA image needs ${width * height * 4} bytes, '
      'got ${rgba.length}',
    );
  }
  final bitmap = LabelBitmap.blank(width, height);
  final bytesPerRow = bitmap.bytesPerRow;
  // Integer form of luminance < threshold, so there is no rounding at the
  // boundary: 127 is black and 128 is white.
  final limit = threshold * 1000;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      if (rgba[i + 3] == 0) continue;
      final luminance = 299 * rgba[i] + 587 * rgba[i + 1] + 114 * rgba[i + 2];
      if (luminance < limit) {
        bitmap.bits[y * bytesPerRow + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }
  }
  return bitmap;
}
