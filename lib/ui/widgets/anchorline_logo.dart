import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/anchorline_colors.dart';
import '../theme/tokens.dart';

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
///                       (anchor body is white). Transparent; the
///                       cut-outs inside the anchor and letters take
///                       the active theme's background colour.
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
    return SvgPicture(
      SvgAssetLoader(
        _assetFor(mark),
        colorMapper: mark == AnchorlineMark.wordmarkDark
            ? HullCutoutMapper(context.palette.surfaceBg)
            : null,
      ),
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

/// Recolours the hull-black shapes of a brand SVG to [surface].
///
/// The dark wordmark draws the gaps inside the anchor ring and letters
/// as hull-black shapes on top of the light ones, which only looks like
/// a hole on a hull-black surface. Mapping them to the surface the mark
/// sits on makes them read as holes on any theme (issue #95). The light
/// and orange brand colours are left as authored.
@immutable
class HullCutoutMapper extends ColorMapper {
  const HullCutoutMapper(this.surface);

  /// The colour of the surface behind the mark.
  final Color surface;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) =>
      color.toARGB32() == AnchorlineColors.hullBlack.toARGB32()
          ? surface
          : color;

  // Equality matters: flutter_svg caches parsed pictures by mapper.
  @override
  bool operator ==(Object other) =>
      other is HullCutoutMapper &&
      other.surface.toARGB32() == surface.toARGB32();

  @override
  int get hashCode => surface.toARGB32().hashCode;
}
