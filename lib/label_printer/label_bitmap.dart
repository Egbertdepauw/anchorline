/// The 1-bit bitmap a label printer prints (issue #114).
///
/// Pure Dart, no Flutter imports. The renderer draws a label, converts it
/// with [bitmapFromRgba], and a printer encoder packs the [LabelBitmap]
/// into its own command bytes.
library;

import 'dart:typed_data';

/// Bitmap width in dots, whatever the label: the print head is 48 mm
/// (384 dots at 203 dpi, the Phomemo M110's 48-byte row). A narrower label
/// is drawn inside this width, see [LabelSize].
const int kLabelWidthDots = 384;

/// Height in dots of the default 50 x 30 mm label (30 mm at 203 dpi). Other
/// sizes have their own, see [LabelSize.heightDots].
const int kLabelHeightDots = 240;

/// All label content stays inside this margin (1.5 mm), because the print
/// head cannot reach the label edge reliably.
const int kLabelSafeMarginDots = 12;

/// How far a 40 mm wide label's left edge sits from the left edge of the
/// 384-dot bitmap: (384 - 320) / 2. The label's content is drawn inside the
/// 320 dots between this offset and the matching one on the right.
///
/// NOT YET VERIFIED ON HARDWARE. It assumes the M110's roll guide centres a
/// 40 mm roll under the 48 mm head. If it sits against one side instead,
/// change this one constant (the label would then also need a left or right
/// flag on [LabelSize]).
const int kNarrowLabelOffsetDots = 32;

/// A label size the printer takes: width across the print head by length
/// along the roll, at 203 dpi (8 dots per mm).
///
/// The bitmap sent to the printer is always [kLabelWidthDots] wide and
/// [heightDots] long; a label narrower than the head only uses the
/// [widthDots] starting at [offsetDots].
enum LabelSize {
  mm50x30('50x30', '50 × 30 mm', widthDots: 384, heightDots: 240),
  mm40x30(
    '40x30',
    '40 × 30 mm',
    widthDots: 320,
    heightDots: 240,
    offsetDots: kNarrowLabelOffsetDots,
  ),
  mm50x50('50x50', '50 × 50 mm', widthDots: 384, heightDots: 400),
  mm50x80('50x80', '50 × 80 mm', widthDots: 384, heightDots: 640);

  const LabelSize(
    this.key,
    this.displayName, {
    required this.widthDots,
    required this.heightDots,
    this.offsetDots = 0,
  });

  /// The stable string stored in the settings, such as `50x30`.
  final String key;

  /// What the picker shows, such as `50 × 30 mm`.
  final String displayName;

  /// The label's own width in dots (at most [kLabelWidthDots]).
  final int widthDots;

  /// The label's length in dots, which is the bitmap's height.
  final int heightDots;

  /// Dots between the bitmap's left edge and the label's left edge.
  final int offsetDots;

  /// The default: the 50 x 30 mm label the app started with.
  static const LabelSize defaultSize = LabelSize.mm50x30;

  /// The size stored as [key]; the default for null or an unknown value.
  static LabelSize fromKey(String? key) {
    for (final s in values) {
      if (s.key == key) return s;
    }
    return defaultSize;
  }

  /// Where content may be drawn: the label inside its own safe margin, in
  /// bitmap dots (left, top, width, height).
  ({double left, double top, double width, double height}) get safeArea => (
    left: (offsetDots + kLabelSafeMarginDots).toDouble(),
    top: kLabelSafeMarginDots.toDouble(),
    width: (widthDots - 2 * kLabelSafeMarginDots).toDouble(),
    height: (heightDots - 2 * kLabelSafeMarginDots).toDouble(),
  );
}

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
