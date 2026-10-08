import 'dart:io';

import 'package:ccrlogger/ui/theme/anchorline_colors.dart';
import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:ccrlogger/ui/widgets/anchorline_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('wordmark asset', () {
    test('has no full-canvas background fill', () {
      final svg =
          File('assets/brand/anchorline-wordmark-dark.svg').readAsStringSync();
      expect(svg.contains('M0 0L1280 0L1280 832L0 832L0 0Z'), isFalse,
          reason: 'the wordmark must be transparent (issue #95)');
    });
  });

  group('HullCutoutMapper', () {
    const surface = Color(0xFF1E1E2E);
    const mapper = HullCutoutMapper(surface);

    test('replaces hull black with the surface colour', () {
      expect(
          mapper.substitute(null, 'path', 'fill', AnchorlineColors.hullBlack),
          surface);
    });

    test('leaves the brand colours alone', () {
      expect(
          mapper.substitute(null, 'path', 'fill', AnchorlineColors.reelOrange),
          AnchorlineColors.reelOrange);
      expect(
          mapper.substitute(
              null, 'path', 'fill', AnchorlineColors.surfaceWhite),
          AnchorlineColors.surfaceWhite);
    });

    test('mappers for the same surface are equal, so the SVG cache is reused',
        () {
      expect(const HullCutoutMapper(surface),
          HullCutoutMapper(Color(surface.toARGB32())));
      expect(const HullCutoutMapper(surface).hashCode,
          HullCutoutMapper(Color(surface.toARGB32())).hashCode);
      expect(const HullCutoutMapper(surface),
          isNot(const HullCutoutMapper(Color(0xFF222222))));
    });
  });

  group('AnchorlineLogo', () {
    Future<SvgAssetLoader> loaderFor(
        WidgetTester tester, AnchorlineMark mark, ThemeData theme) async {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(body: AnchorlineLogo(mark: mark, size: 32)),
      ));
      final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
      return picture.bytesLoader as SvgAssetLoader;
    }

    testWidgets('the dark wordmark cuts its holes in the theme background',
        (tester) async {
      final theme = AppThemes.byId('catppuccin');
      final loader =
          await loaderFor(tester, AnchorlineMark.wordmarkDark, theme.themeData);
      expect(loader.colorMapper, HullCutoutMapper(theme.palette.surfaceBg));
    });

    testWidgets('follows a different theme', (tester) async {
      final theme = AppThemes.byId('miasma');
      final loader =
          await loaderFor(tester, AnchorlineMark.wordmarkDark, theme.themeData);
      expect(loader.colorMapper, HullCutoutMapper(theme.palette.surfaceBg));
    });

    testWidgets('other marks are drawn as authored', (tester) async {
      final loader = await loaderFor(tester, AnchorlineMark.inline,
          AppThemes.byId('catppuccin').themeData);
      expect(loader.colorMapper, isNull);
    });
  });
}
