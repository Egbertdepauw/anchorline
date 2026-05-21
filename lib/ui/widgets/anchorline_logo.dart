import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Which of the Anchorline brand marks to render. Each value maps to
/// one of the SVGs under `assets/brand/`.
///
/// Picking the right one:
///   - [full]          — splash / about / launch / hero surfaces
///                       (dark tile baked in).
///   - [icon]          — compact UI affordances on a dark surface
///                       (anchor only).
///   - [inline]        — anywhere you'd otherwise put an icon glyph.
///                       Anchor in orange, transparent background,
///                       sits cleanly on light OR dark.
///   - [wordmarkDark]  — horizontal lockup; use on dark surfaces
///                       (anchor body is white).
///   - [wordmarkLight] — horizontal lockup; use on light surfaces
///                       (anchor body is dark).
enum AnchorlineMark { full, icon, inline, wordmarkDark, wordmarkLight }

/// Renders the Anchorline brand mark.
///
/// The refined brand SVGs have their colours baked into the paths
/// (the anchor body is NOT `currentColor`), so we deliberately do
/// not apply a `colorFilter` — that would flatten the multi-colour
/// mark to one tint. Pick the right [AnchorlineMark] variant for the
/// surface you're rendering on.
///
/// Examples:
/// ```dart
/// // 96 px tall full mark on a dark splash:
/// const AnchorlineLogo(mark: AnchorlineMark.full, size: 96)
///
/// // Wordmark in an app bar (dark background):
/// const AnchorlineLogo(mark: AnchorlineMark.wordmarkDark, size: 28)
///
/// // Inline anchor next to a dive site name on either background:
/// const AnchorlineLogo(mark: AnchorlineMark.inline, size: 18)
/// ```
class AnchorlineLogo extends StatelessWidget {
  const AnchorlineLogo({
    super.key,
    required this.mark,
    this.size,
    this.semanticLabel,
  });

  final AnchorlineMark mark;

  /// Logical-pixel height. When null, the SVG renders at its
  /// intrinsic size.
  final double? size;

  /// Optional accessibility label — defaults to "Anchorline" when
  /// null.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _assetFor(mark),
      height: size,
      semanticsLabel: semanticLabel ?? 'Anchorline',
    );
  }

  static String _assetFor(AnchorlineMark mark) => switch (mark) {
        AnchorlineMark.full => 'assets/brand/anchorline-mark-full.svg',
        AnchorlineMark.icon => 'assets/brand/anchorline-mark-icon.svg',
        AnchorlineMark.inline => 'assets/brand/anchorline-mark-inline.svg',
        AnchorlineMark.wordmarkDark =>
          'assets/brand/anchorline-wordmark-dark.svg',
        AnchorlineMark.wordmarkLight =>
          'assets/brand/anchorline-wordmark-light.svg',
      };
}
