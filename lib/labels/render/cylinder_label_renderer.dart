/// Draws a [CylinderLabel] as the 1-bit bitmap a label printer prints
/// (issue #114).
///
/// The only Flutter code under `lib/labels/`. The label model decides every
/// number and string; this file only lays them out, at printer resolution
/// (384 x 240 dots, 203 dpi), with all ink inside the 12-dot safe margin:
///
/// ```
/// ┌──────────────────────────────────────┐
/// │█ [DIL] Tx21/35 ███████████████ EdP ██│  black bar, white text
/// │                                      │
/// │               67 m                   │  headline, as large as fits
/// │                  MOD 1.6             │
/// │ 1.3: 53 m              MOD 1.6: 67 m │  diluent only
/// │ O2 20.6  He 33.8           31 Oct 26 │  footer
/// └──────────────────────────────────────┘
/// ```
///
/// * The mix name is never shortened. The initials after it get whatever
///   width is left, ellipsized, and are left out when there is no room.
/// * The headline font shrinks until the number, the `m` and the caption
///   fit the content width. `130 m` (Tx11/70) is the design case; a 2-digit
///   depth is as tall as the space between the bar and the footer allows.
/// * Thermal printing at 203 dpi loses thin strokes and small text, so
///   everything is Inter at weight 800 and the small text keeps a cap height
///   of about 19 dots.
///
/// Text is placed by its cap box (baseline up to the top of a capital or a
/// digit), so the layout doesn't depend on the font's line spacing. The
/// rects in [CylinderLabelRender] are those cap boxes, across the text's
/// advance width; round glyphs overshoot them by a dot or two and
/// descenders hang below.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../label_printer/label_bitmap.dart';
import '../cylinder_label.dart';

/// A rendered label plus where each element was drawn, in dots. Tests use
/// the rects to check the layout without comparing pixels.
class CylinderLabelRender {
  const CylinderLabelRender({
    required this.bitmap,
    required this.bar,
    required this.mixName,
    required this.initials,
    required this.tag,
    required this.headline,
  });

  final LabelBitmap bitmap;

  /// The black bar along the top.
  final Rect bar;

  /// The mix name in the bar.
  final Rect mixName;

  /// The "analysed by" initials in the bar; null when there are none, or no
  /// room for them.
  final Rect? initials;

  /// The outlined `DIL` tag (its outer edge); null on a bailout/deco label.
  final Rect? tag;

  /// The headline: the depth, its `m` and the caption beside them.
  final Rect headline;
}

/// Renders [label] and reports where each element went.
Future<CylinderLabelRender> renderCylinderLabelWithLayout(
  CylinderLabel label,
) async {
  final recorder = ui.PictureRecorder();
  final layout = _paintLabel(Canvas(recorder, _kCanvas), label);
  final picture = recorder.endRecording();
  final ui.Image image;
  try {
    image = await picture.toImage(kLabelWidthDots, kLabelHeightDots);
  } finally {
    picture.dispose();
  }
  final ByteData? rgba;
  try {
    // Premultiplied, which is fine: the background is opaque white, so
    // alpha is 255 everywhere.
    rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  } finally {
    image.dispose();
  }
  if (rgba == null) {
    throw StateError('Could not read the rendered label pixels');
  }
  return CylinderLabelRender(
    bitmap: bitmapFromRgba(
      rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
      kLabelWidthDots,
      kLabelHeightDots,
    ),
    bar: layout.bar,
    mixName: layout.mixName,
    initials: layout.initials,
    tag: layout.tag,
    headline: layout.headline,
  );
}

/// The bitmap to print for [label].
Future<LabelBitmap> renderCylinderLabel(CylinderLabel label) async =>
    (await renderCylinderLabelWithLayout(label)).bitmap;

/// The 1-bit render of [label] as a black-and-white image, exactly what
/// the printer gets. For golden tests and an on-screen preview. The caller
/// disposes the image.
Future<ui.Image> renderCylinderLabelImage(CylinderLabel label) async {
  final bitmap = await renderCylinderLabel(label);
  final pixels = Uint8List(bitmap.width * bitmap.height * 4);
  for (var y = 0; y < bitmap.height; y++) {
    for (var x = 0; x < bitmap.width; x++) {
      final i = (y * bitmap.width + x) * 4;
      final v = bitmap.isBlack(x, y) ? 0 : 255;
      pixels[i] = v;
      pixels[i + 1] = v;
      pixels[i + 2] = v;
      pixels[i + 3] = 255;
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    bitmap.width,
    bitmap.height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

// ---------------------------------------------------------------------------
// Layout, in dots.

final Rect _kCanvas = Rect.fromLTWH(
  0,
  0,
  kLabelWidthDots.toDouble(),
  kLabelHeightDots.toDouble(),
);

/// Everything is drawn inside this, and the canvas is clipped to it.
final Rect _kSafe = _kCanvas.deflate(kLabelSafeMarginDots.toDouble());

/// Black bar along the top of the safe area.
const double _kBarHeight = 52;

/// Inset of the bar's text from the bar's left and right ends.
const double _kBarPadding = 10;

/// Mix name: design size, and the floor it may shrink to so a long name
/// still fits whole.
const double _kMixNameSize = 40;
const double _kMixNameMinSize = 20;

/// The `DIL` tag: outlined box, vertically centred in the bar.
const double _kTagHeight = 34;
const double _kTagStroke = 3;
const double _kTagRadius = 5;
const double _kTagTextSize = 24;
const double _kTagPaddingX = 7;

/// Space between the tag and the mix name.
const double _kTagGap = 10;

/// Initials: same size as the footer, and the narrowest space worth
/// drawing them in (less than this would be a letter and an ellipsis).
const double _kInitialsSize = 26;
const double _kInitialsMinWidth = 48;

/// Space between the mix name and the initials.
const double _kInitialsGap = 16;

/// Footer, diluent line and headline caption: 26 gives a 19-dot cap
/// height. The footer is the widest line and is about as wide as the label
/// allows at this size, so the footer and diluent line shrink together, by
/// a dot or two, when a date like `28 May 26` would leave too small a gap.
const double _kSmallSize = 26;
const double _kSmallMinSize = 18;

/// The smallest space between the left and right halves of the footer and
/// the diluent line, so they never read as one run of text: nearly twice
/// the double space inside `O2 20.6  He 33.8` (11 dots at size 26).
const double _kSplitMinGap = 20;

/// Space between the diluent line's baseline and the footer's cap line.
const double _kSmallLineGap = 10;

/// Space between the bar and the headline's cap line, and between the
/// headline's baseline and the line below it.
const double _kHeadlineGapTop = 12;
const double _kHeadlineGapBottom = 14;

/// The headline's floor; never reached by a real depth.
const double _kHeadlineMinSize = 40;

/// The `m` after the depth, as a fraction of the headline size.
const double _kUnitScale = 0.36;

/// Space between the depth and the `m`/caption column.
const double _kUnitGap = 8;

/// Space between the `m` and the caption under it.
const double _kCaptionGap = 8;

// ---------------------------------------------------------------------------
// Type.

const String _kFontFamily = 'Inter';

/// Inter's cap height (OS/2 sCapHeight 1490 / unitsPerEm 2048). It is the
/// same for every weight and optical size, so text is placed by it.
const double _kCapHeightEm = 1490 / 2048;

/// Inter's descender (494 / 2048): the furthest any glyph reaches below the
/// baseline.
const double _kDescentEm = 494 / 2048;

/// Inter's optical-size axis: 14 (text) for everything at label text sizes,
/// 32 (display) for the headline, which is over 50 pt on paper.
const double _kTextOpsz = 14;
const double _kDisplayOpsz = 32;

const Color _kBlack = Color(0xFF000000);
const Color _kWhite = Color(0xFFFFFFFF);

typedef _Layout = ({
  Rect bar,
  Rect mixName,
  Rect? initials,
  Rect? tag,
  Rect headline,
});

/// One line of text in Inter 800, placed by its baseline.
class _Line {
  _Line(
    String text, {
    required this.size,
    required Color color,
    required double opsz,
    double? maxWidth,
  }) : _painter = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontFamily: _kFontFamily,
              fontSize: size,
              fontWeight: FontWeight.w800,
              fontVariations: [
                const FontVariation('wght', 800),
                FontVariation('opsz', opsz),
              ],
              color: color,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: maxWidth == null ? null : '…',
          // Report the width of the (possibly ellipsized) text itself, not
          // the space it was given, so right-aligned text ends at its edge.
          textWidthBasis: TextWidthBasis.longestLine,
        )..layout(maxWidth: maxWidth ?? double.infinity);

  final double size;
  final TextPainter _painter;

  double get width => _painter.width;
  double get capHeight => size * _kCapHeightEm;

  /// Paints with the start of the baseline at ([x], [baseline]) and
  /// returns the cap box.
  Rect paint(Canvas canvas, double x, double baseline) {
    final top = baseline -
        _painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    _painter.paint(canvas, Offset(x, top));
    return Rect.fromLTRB(x, baseline - capHeight, x + width, baseline);
  }

  void dispose() => _painter.dispose();
}

/// Lays out [_Line]s for one render and disposes them all at the end, the
/// ones only measured while fitting a size included.
class _Lines {
  final _made = <_Line>[];

  _Line call(
    String text, {
    required double size,
    Color color = _kBlack,
    double opsz = _kTextOpsz,
    double? maxWidth,
  }) {
    final l = _Line(text,
        size: size, color: color, opsz: opsz, maxWidth: maxWidth);
    _made.add(l);
    return l;
  }

  void dispose() {
    for (final l in _made) {
      l.dispose();
    }
  }
}

/// The largest whole size from [max] down to [min] at which [fits] holds,
/// or [min] when none does.
double _fitSize(double max, double min, bool Function(double size) fits) {
  var size = max;
  while (size > min && !fits(size)) {
    size -= 1;
  }
  return size;
}

/// The baseline that vertically centres text with [capHeight] on [centre],
/// rounded to a whole dot so the strokes print crisp.
double _centredBaseline(double centre, double capHeight) =>
    (centre + capHeight / 2).roundToDouble();

_Layout _paintLabel(Canvas canvas, CylinderLabel label) {
  final line = _Lines();
  try {
    canvas.drawRect(_kCanvas, Paint()..color = _kWhite);
    canvas.clipRect(_kSafe);

    // Bar: [tag] mix name ............ initials
    final bar = Rect.fromLTWH(
      _kSafe.left,
      _kSafe.top,
      _kSafe.width,
      _kBarHeight,
    );
    canvas.drawRect(bar, Paint()..color = _kBlack);
    var x = bar.left + _kBarPadding;
    final textRight = bar.right - _kBarPadding;

    Rect? tag;
    final tagText = label.barTag;
    if (tagText != null) {
      tag = _paintTag(canvas, line, tagText, left: x, centre: bar.center.dy);
      x = tag.right + _kTagGap;
    }

    // Never shortened: shrinks instead, though every name the app makes
    // fits at the design size.
    final nameSpace = textRight - x;
    final nameSize = _fitSize(
      _kMixNameSize,
      _kMixNameMinSize,
      (s) => line(label.mixName, size: s).width <= nameSpace,
    );
    final name = line(label.mixName, size: nameSize, color: _kWhite);
    final mixName =
        name.paint(canvas, x, _centredBaseline(bar.center.dy, name.capHeight));

    Rect? initials;
    final by = label.analysedBy;
    final initialsSpace = textRight - (mixName.right + _kInitialsGap);
    if (by != null && initialsSpace >= _kInitialsMinWidth) {
      final i = line(
        by,
        size: _kInitialsSize,
        color: _kWhite,
        maxWidth: initialsSpace,
      );
      initials = i.paint(
        canvas,
        textRight - i.width,
        _centredBaseline(bar.center.dy, i.capHeight),
      );
    }

    // Footer along the bottom margin, the diluent line above it, both at
    // one size.
    final dilLeft = label.diluentLeft;
    final dilRight = label.diluentRight;
    final splitLines = [
      (label.footerLeft, label.footerRight),
      if (dilLeft != null && dilRight != null) (dilLeft, dilRight),
    ];
    final smallSize = _fitSize(
      _kSmallSize,
      _kSmallMinSize,
      (s) => splitLines.every(
        (p) =>
            line(p.$1, size: s).width +
                _kSplitMinGap +
                line(p.$2, size: s).width <=
            _kSafe.width,
      ),
    );
    // Low enough for descenders (the "p" in "Sep") to end at the margin.
    var baseline = (_kSafe.bottom - smallSize * _kDescentEm).floorToDouble();
    var smallTop = baseline;
    for (final (left, right) in splitLines) {
      final l = line(left, size: smallSize);
      final r = line(right, size: smallSize);
      l.paint(canvas, _kSafe.left, baseline);
      r.paint(canvas, _kSafe.right - r.width, baseline);
      smallTop = baseline - l.capHeight;
      baseline = (smallTop - _kSmallLineGap).floorToDouble();
    }

    final headline = _paintHeadline(
      canvas,
      line,
      label,
      top: bar.bottom + _kHeadlineGapTop,
      bottom: smallTop - _kHeadlineGapBottom,
    );

    return (
      bar: bar,
      mixName: mixName,
      initials: initials,
      tag: tag,
      headline: headline,
    );
  } finally {
    line.dispose();
  }
}

/// Paints [text] in a white outlined box starting at [left], vertically
/// centred on [centre]. Returns the box's outer edge.
Rect _paintTag(
  Canvas canvas,
  _Lines line,
  String text, {
  required double left,
  required double centre,
}) {
  final t = line(text, size: _kTagTextSize, color: _kWhite);
  final box = Rect.fromLTWH(
    left,
    (centre - _kTagHeight / 2).roundToDouble(),
    (t.width + 2 * (_kTagStroke + _kTagPaddingX)).ceilToDouble(),
    _kTagHeight,
  );
  // The stroke runs half a stroke inside the box, so the outline covers
  // whole dots and its outer edge is exactly [box].
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      box.deflate(_kTagStroke / 2),
      const Radius.circular(_kTagRadius),
    ),
    Paint()
      ..color = _kWhite
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kTagStroke,
  );
  t.paint(
    canvas,
    box.left + (box.width - t.width) / 2,
    _centredBaseline(box.center.dy, t.capHeight),
  );
  return box;
}

/// Paints the depth, its `m` and the caption, centred across the safe
/// width, with the depth's cap box filling [top] to [bottom] unless the
/// width limits it. The caption shares the depth's baseline and the `m`
/// sits on top of the caption.
Rect _paintHeadline(
  Canvas canvas,
  _Lines line,
  CylinderLabel label, {
  required double top,
  required double bottom,
}) {
  // No unit after the dash shown when there is no usable depth.
  final unit = label.headlineMeters == null ? null : 'm';
  final caption = line(label.headlineCaption, size: _kSmallSize);

  double groupWidth(double size) {
    final number = line(label.headlineText, size: size, opsz: _kDisplayOpsz);
    final unitWidth = unit == null
        ? 0.0
        : line(unit, size: size * _kUnitScale, opsz: _kDisplayOpsz).width;
    return number.width + _kUnitGap + math.max(unitWidth, caption.width);
  }

  final size = _fitSize(
    ((bottom - top) / _kCapHeightEm).floorToDouble(),
    _kHeadlineMinSize,
    (s) => groupWidth(s) <= _kSafe.width,
  );
  final number = line(label.headlineText, size: size, opsz: _kDisplayOpsz);
  final left = _kSafe.left + (_kSafe.width - groupWidth(size)) / 2;
  final baseline =
      (top + (bottom - top + number.capHeight) / 2).floorToDouble();
  final numberBox = number.paint(canvas, left, baseline);

  final columnLeft = numberBox.right + _kUnitGap;
  final captionBox = caption.paint(canvas, columnLeft, baseline);
  var right = captionBox.right;
  if (unit != null) {
    final u = line(unit, size: size * _kUnitScale, opsz: _kDisplayOpsz);
    final unitBox = u.paint(
      canvas,
      columnLeft,
      (captionBox.top - _kCaptionGap).floorToDouble(),
    );
    right = math.max(right, unitBox.right);
  }
  return Rect.fromLTRB(numberBox.left, numberBox.top, right, numberBox.bottom);
}
