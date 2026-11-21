/// Draws a [CylinderLabel] as the 1-bit bitmap a label printer prints
/// (issue #114).
///
/// The only Flutter code under `lib/labels/`. The label model decides every
/// number and string; this file only lays them out, at printer resolution
/// (203 dpi, 384 dots wide, the height of the [LabelSize]), with all ink
/// inside the 12-dot safe margin. The 50 x 30 mm layout:
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
/// The OC label (Backgas) is laid out like the diluent one: an `OC` tag, the
/// headline captioned `ppO2 1.4`, and a centred `MOD 1.6: 67 m` line in
/// place of the diluent line.
///
/// The sizes differ only in their [_Metrics]. A 40 mm wide label is drawn in
/// the 320 dots centred in the bitmap (see [kNarrowLabelOffsetDots]). The
/// 50 x 50 and 50 x 80 mm labels put the bar on top and the footer at the
/// bottom, and stack the headline (the depth with its `m`, the caption
/// centred under it) in the space between, so the depth gets the full width.
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
///
/// [rotateTallCentre] turns the headline of a 50 x 80 mm label 90° (see
/// [_kTallCentreTurn]); it does nothing on the other sizes.
Future<CylinderLabelRender> renderCylinderLabelWithLayout(
  CylinderLabel label, [
  LabelSize size = LabelSize.defaultSize,
  bool rotateTallCentre = false,
]) async {
  final recorder = ui.PictureRecorder();
  final layout = _paintLabel(
    Canvas(recorder, _canvasFor(size)),
    label,
    size,
    rotateTallCentre: rotateTallCentre,
  );
  final picture = recorder.endRecording();
  final ui.Image image;
  try {
    image = await picture.toImage(kLabelWidthDots, size.heightDots);
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
      size.heightDots,
    ),
    bar: layout.bar,
    mixName: layout.mixName,
    initials: layout.initials,
    tag: layout.tag,
    headline: layout.headline,
  );
}

/// The bitmap to print for [label] on a label of [size].
Future<LabelBitmap> renderCylinderLabel(
  CylinderLabel label, [
  LabelSize size = LabelSize.defaultSize,
  bool rotateTallCentre = false,
]) async =>
    (await renderCylinderLabelWithLayout(label, size, rotateTallCentre))
        .bitmap;

/// The 1-bit render of [label] as a black-and-white image, exactly what
/// the printer gets. For golden tests and an on-screen preview. The caller
/// disposes the image.
Future<ui.Image> renderCylinderLabelImage(
  CylinderLabel label, [
  LabelSize size = LabelSize.defaultSize,
  bool rotateTallCentre = false,
]) async {
  final bitmap = await renderCylinderLabel(label, size, rotateTallCentre);
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

Rect _canvasFor(LabelSize size) =>
    Rect.fromLTWH(0, 0, kLabelWidthDots.toDouble(), size.heightDots.toDouble());

/// Everything is drawn inside this, and the canvas is clipped to it: the
/// label inside its own safe margin.
Rect _safeFor(LabelSize size) {
  final a = size.safeArea;
  return Rect.fromLTWH(a.left, a.top, a.width, a.height);
}

/// Every size-dependent number of the layout, in dots. [_Metrics.of] gives
/// the set for a [LabelSize]; the 50 x 30 mm set is the original design and
/// its output must not change.
///
/// Thermal printing at 203 dpi loses thin strokes and small text, so no set
/// goes under a 3-dot stroke, and small text keeps a cap height of about
/// 19 dots (size 26) wherever the width allows. The 40 mm label is 64 dots
/// narrower, so its footer shrinks (to about 21, a 15-dot cap) instead.
class _Metrics {
  const _Metrics({
    required this.barHeight,
    required this.barPadding,
    required this.mixNameSize,
    required this.tagHeight,
    required this.tagTextSize,
    required this.tagPaddingX,
    required this.initialsSize,
    required this.smallSize,
    required this.smallMinSize,
    required this.smallLineGap,
    required this.headlineGapTop,
    required this.headlineGapBottom,
    required this.captionSize,
    this.stacked = false,
    this.mixNameReserveMinSize,
  });

  /// Black bar along the top of the safe area, and the inset of the bar's
  /// text from the bar's left and right ends.
  final double barHeight;
  final double barPadding;

  /// Mix name: design size. It may shrink to [_kMixNameMinSize] so a long
  /// name still fits whole.
  final double mixNameSize;

  /// The `DIL` / `OC` tag: outlined box, vertically centred in the bar.
  final double tagHeight;
  final double tagTextSize;
  final double tagPaddingX;

  /// Initials: the size of the footer, give or take.
  final double initialsSize;

  /// Footer, diluent / OC line: the design size and the floor it shrinks
  /// to when a wide line would leave too small a gap between its halves.
  final double smallSize;
  final double smallMinSize;

  /// Space between a small line's baseline and the cap line of the one
  /// below it.
  final double smallLineGap;

  /// Space between the bar and the headline's cap line, and between the
  /// headline's baseline and the line below it.
  final double headlineGapTop;
  final double headlineGapBottom;

  /// The headline caption's size (`MOD 1.6`).
  final double captionSize;

  /// Whether the caption sits centred under the depth (tall labels) rather
  /// than beside it, with the `m` on top of it (30 mm labels).
  final bool stacked;

  /// When set, the mix name may shrink down to this size to leave room for
  /// the whole initials after it, rather than the initials being left out.
  /// Null (50 x 30): the name keeps its size and the initials take what is
  /// left.
  final double? mixNameReserveMinSize;

  static const _short = _Metrics(
    barHeight: 52,
    barPadding: 10,
    mixNameSize: 40,
    tagHeight: 34,
    tagTextSize: 24,
    tagPaddingX: 7,
    initialsSize: 26,
    smallSize: 26,
    smallMinSize: 18,
    smallLineGap: 10,
    headlineGapTop: 12,
    headlineGapBottom: 14,
    captionSize: 26,
  );

  // 320 dots wide: the footer's own width needs size 21 or so.
  static const _narrow = _Metrics(
    barHeight: 52,
    barPadding: 10,
    mixNameSize: 40,
    tagHeight: 32,
    tagTextSize: 22,
    tagPaddingX: 6,
    initialsSize: 22,
    smallSize: 26,
    smallMinSize: 16,
    smallLineGap: 10,
    headlineGapTop: 12,
    headlineGapBottom: 14,
    captionSize: 22,
    mixNameReserveMinSize: 30,
  );

  static const _tall50 = _Metrics(
    barHeight: 60,
    barPadding: 10,
    mixNameSize: 44,
    tagHeight: 38,
    tagTextSize: 26,
    tagPaddingX: 8,
    initialsSize: 28,
    smallSize: 26,
    smallMinSize: 18,
    smallLineGap: 12,
    headlineGapTop: 24,
    headlineGapBottom: 24,
    captionSize: 34,
    stacked: true,
    mixNameReserveMinSize: 40,
  );

  static const _tall80 = _Metrics(
    barHeight: 72,
    barPadding: 12,
    mixNameSize: 48,
    tagHeight: 42,
    tagTextSize: 28,
    tagPaddingX: 9,
    initialsSize: 30,
    smallSize: 26,
    smallMinSize: 18,
    smallLineGap: 14,
    headlineGapTop: 40,
    headlineGapBottom: 40,
    captionSize: 40,
    stacked: true,
    mixNameReserveMinSize: 40,
  );

  static _Metrics of(LabelSize size) => switch (size) {
    LabelSize.mm50x30 => _short,
    LabelSize.mm40x30 => _narrow,
    LabelSize.mm50x50 => _tall50,
    LabelSize.mm50x80 => _tall80,
  };
}

/// The mix name's floor.
const double _kMixNameMinSize = 20;

/// Which way the rotated centre of the 50 x 80 mm label turns, in radians
/// for [Canvas.rotate]: -pi/2 is a quarter turn counterclockwise, so the
/// depth reads from the bottom of the label to the top (tilt your head
/// left) and the tops of the letters point at the label's left edge. To
/// read the other way, use +pi/2 and mirror the translate in
/// [_paintRotatedHeadline].
const double _kTallCentreTurn = -math.pi / 2;

/// Space above and below the rotated centre, against the bar and the lines
/// at the bottom. Less than the upright gap: the rotated block's long side
/// is the one that needs the room.
const double _kRotatedCentreGap = 24;

/// The tag's outline and corner.
const double _kTagStroke = 3;
const double _kTagRadius = 5;

/// Space between the tag and the mix name.
const double _kTagGap = 10;

/// The narrowest space worth drawing initials in (less than this would be a
/// letter and an ellipsis).
const double _kInitialsMinWidth = 48;

/// Space between the mix name and the initials.
const double _kInitialsGap = 16;

/// The smallest space between the left and right halves of the footer and
/// the diluent line, so they never read as one run of text: nearly twice
/// the double space inside `O2 20.6  He 33.8` (11 dots at size 26).
const double _kSplitMinGap = 20;

/// The headline's floor; never reached by a real depth.
const double _kHeadlineMinSize = 40;

/// The `m` after the depth, as a fraction of the headline size.
const double _kUnitScale = 0.36;

/// Space between the depth and the `m`/caption column.
const double _kUnitGap = 8;

/// Space between the `m` and the caption under it, and (stacked) between
/// the depth's baseline and the caption's cap line.
const double _kCaptionGap = 8;
const double _kStackedCaptionGap = 18;

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

_Layout _paintLabel(
  Canvas canvas,
  CylinderLabel label,
  LabelSize size, {
  bool rotateTallCentre = false,
}) {
  final line = _Lines();
  try {
    final m = _Metrics.of(size);
    final safe = _safeFor(size);
    canvas.drawRect(_canvasFor(size), Paint()..color = _kWhite);
    canvas.clipRect(safe);

    // Bar: [tag] mix name ............ initials
    final bar = Rect.fromLTWH(safe.left, safe.top, safe.width, m.barHeight);
    canvas.drawRect(bar, Paint()..color = _kBlack);
    var x = bar.left + m.barPadding;
    final textRight = bar.right - m.barPadding;

    Rect? tag;
    final tagText = label.barTag;
    if (tagText != null) {
      tag = _paintTag(canvas, line, m, tagText, left: x, centre: bar.center.dy);
      x = tag.right + _kTagGap;
    }

    // Never shortened: shrinks instead, though every name the app makes
    // fits at the design size.
    final nameSpace = textRight - x;
    var nameSize = _fitSize(
      m.mixNameSize,
      _kMixNameMinSize,
      (s) => line(label.mixName, size: s).width <= nameSpace,
    );
    // On the 40 mm and tall labels the initials are part of the design, so
    // the name gives up a few dots of size (down to
    // [_Metrics.mixNameReserveMinSize]) to leave them room, rather than
    // leaving them out. The 50 x 30 label keeps its sizes.
    final by = label.analysedBy;
    final reserveMin = m.mixNameReserveMinSize;
    var initialsReserved = false;
    if (reserveMin != null && by != null) {
      final initialsWidth = line(by, size: m.initialsSize).width;
      final reserved = initialsWidth + _kInitialsGap;
      final shrunk = _fitSize(
        m.mixNameSize,
        reserveMin,
        (s) => line(label.mixName, size: s).width <= nameSpace - reserved,
      );
      if (line(label.mixName, size: shrunk).width <= nameSpace - reserved) {
        nameSize = shrunk;
        initialsReserved = true;
      }
    }
    final name = line(label.mixName, size: nameSize, color: _kWhite);
    final mixName = name.paint(
      canvas,
      x,
      _centredBaseline(bar.center.dy, name.capHeight),
    );

    Rect? initials;
    final initialsSpace = textRight - (mixName.right + _kInitialsGap);
    if (by != null &&
        (initialsReserved || initialsSpace >= _kInitialsMinWidth)) {
      final i = line(
        by,
        size: m.initialsSize,
        color: _kWhite,
        maxWidth: initialsSpace,
      );
      initials = i.paint(
        canvas,
        textRight - i.width,
        _centredBaseline(bar.center.dy, i.capHeight),
      );
    }

    // Footer along the bottom margin, the diluent / OC line above it, both
    // at one size. A pair is left and right; a line with no right half (the
    // OC line) is centred.
    final dilLeft = label.diluentLeft;
    final dilRight = label.diluentRight;
    final ocMod = label.ocModLine;
    final splitLines = <(String, String?)>[
      (label.footerLeft, label.footerRight),
      if (dilLeft != null && dilRight != null) (dilLeft, dilRight),
      if (ocMod != null) (ocMod, null),
    ];
    final smallSize = _fitSize(
      m.smallSize,
      m.smallMinSize,
      (s) => splitLines.every((p) {
        final right = p.$2;
        return right == null
            ? line(p.$1, size: s).width <= safe.width
            : line(p.$1, size: s).width +
                      _kSplitMinGap +
                      line(right, size: s).width <=
                  safe.width;
      }),
    );
    // Low enough for descenders (the "p" in "Sep") to end at the margin.
    var baseline = (safe.bottom - smallSize * _kDescentEm).floorToDouble();
    var smallTop = baseline;
    for (final (left, right) in splitLines) {
      final l = line(left, size: smallSize);
      if (right == null) {
        l.paint(canvas, safe.left + (safe.width - l.width) / 2, baseline);
      } else {
        l.paint(canvas, safe.left, baseline);
        final r = line(right, size: smallSize);
        r.paint(canvas, safe.right - r.width, baseline);
      }
      smallTop = baseline - l.capHeight;
      baseline = (smallTop - m.smallLineGap).floorToDouble();
    }

    final headline = rotateTallCentre && size == LabelSize.mm50x80
        ? _paintRotatedHeadline(
            canvas,
            line,
            label,
            m,
            safe,
            top: bar.bottom + _kRotatedCentreGap,
            bottom: smallTop - _kRotatedCentreGap,
          )
        : _paintHeadline(
            canvas,
            line,
            label,
            m,
            safe,
            top: bar.bottom + m.headlineGapTop,
            bottom: smallTop - m.headlineGapBottom,
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
  _Metrics m,
  String text, {
  required double left,
  required double centre,
}) {
  final t = line(text, size: m.tagTextSize, color: _kWhite);
  final box = Rect.fromLTWH(
    left,
    (centre - m.tagHeight / 2).roundToDouble(),
    (t.width + 2 * (_kTagStroke + m.tagPaddingX)).ceilToDouble(),
    m.tagHeight,
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
/// width limits it.
///
/// Beside (30 mm labels): the caption shares the depth's baseline and the
/// `m` sits on top of the caption. Stacked (tall labels): the `m` follows
/// the depth on its baseline and the caption is centred under the pair, the
/// whole block centred between [top] and [bottom].
Rect _paintHeadline(
  Canvas canvas,
  _Lines line,
  CylinderLabel label,
  _Metrics m,
  Rect safe, {
  required double top,
  required double bottom,
}) {
  // No unit after the dash shown when there is no usable depth.
  final unit = label.headlineMeters == null ? null : 'm';
  final caption = line(label.headlineCaption, size: m.captionSize);

  if (m.stacked) {
    return _paintStackedHeadline(
      canvas,
      line,
      label,
      m,
      safe,
      unit,
      caption,
      top: top,
      bottom: bottom,
    );
  }

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
    (s) => groupWidth(s) <= safe.width,
  );
  final number = line(label.headlineText, size: size, opsz: _kDisplayOpsz);
  final left = safe.left + (safe.width - groupWidth(size)) / 2;
  final baseline = (top + (bottom - top + number.capHeight) / 2)
      .floorToDouble();
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

/// The stacked headline turned by [_kTallCentreTurn], filling the box
/// between [top] and [bottom] across the safe width. In the turned frame the
/// box is as wide as it is tall on the label, so the depth can get bigger
/// than across the 360 dots of the label's width. Returns the bounds of
/// what was drawn, in label dots.
Rect _paintRotatedHeadline(
  Canvas canvas,
  _Lines line,
  CylinderLabel label,
  _Metrics m,
  Rect safe, {
  required double top,
  required double bottom,
}) {
  final unit = label.headlineMeters == null ? null : 'm';
  final caption = line(label.headlineCaption, size: m.captionSize);
  // Local frame: x runs up the label, y runs to the label's right, with
  // the origin at the box's bottom left corner.
  final localBox = Rect.fromLTWH(0, 0, bottom - top, safe.width);
  canvas.save();
  canvas.translate(safe.left, bottom);
  canvas.rotate(_kTallCentreTurn);
  final local = _paintStackedHeadline(
    canvas,
    line,
    label,
    m,
    localBox,
    unit,
    caption,
    top: localBox.top,
    bottom: localBox.bottom,
  );
  canvas.restore();
  // (x, y) in the local frame is (safe.left + y, bottom - x) on the label.
  return Rect.fromLTRB(
    safe.left + local.top,
    bottom - local.right,
    safe.left + local.bottom,
    bottom - local.left,
  );
}

Rect _paintStackedHeadline(
  Canvas canvas,
  _Lines line,
  CylinderLabel label,
  _Metrics m,
  Rect safe,
  String? unit,
  _Line caption, {
  required double top,
  required double bottom,
}) {
  double rowWidth(double size) {
    final number = line(label.headlineText, size: size, opsz: _kDisplayOpsz);
    final unitWidth = unit == null
        ? 0.0
        : line(unit, size: size * _kUnitScale, opsz: _kDisplayOpsz).width;
    return number.width + (unit == null ? 0 : _kUnitGap + unitWidth);
  }

  // The depth's cap height, the gap and the caption's cap height must all
  // fit the space as well as the row fitting the width.
  final maxByHeight =
      ((bottom - top - _kStackedCaptionGap - caption.capHeight) / _kCapHeightEm)
          .floorToDouble();
  final size = _fitSize(
    maxByHeight,
    _kHeadlineMinSize,
    (s) => rowWidth(s) <= safe.width,
  );
  final number = line(label.headlineText, size: size, opsz: _kDisplayOpsz);
  final blockHeight =
      number.capHeight + _kStackedCaptionGap + caption.capHeight;
  final numberBaseline =
      (top + (bottom - top - blockHeight) / 2 + number.capHeight)
          .floorToDouble();
  final left = safe.left + (safe.width - rowWidth(size)) / 2;
  final numberBox = number.paint(canvas, left, numberBaseline);
  var right = numberBox.right;
  if (unit != null) {
    final u = line(unit, size: size * _kUnitScale, opsz: _kDisplayOpsz);
    right = u.paint(canvas, numberBox.right + _kUnitGap, numberBaseline).right;
  }
  final captionBox = caption.paint(
    canvas,
    safe.left + (safe.width - caption.width) / 2,
    (numberBaseline + _kStackedCaptionGap + caption.capHeight).floorToDouble(),
  );
  return Rect.fromLTRB(
    math.min(numberBox.left, captionBox.left),
    numberBox.top,
    math.max(right, captionBox.right),
    captionBox.bottom,
  );
}
