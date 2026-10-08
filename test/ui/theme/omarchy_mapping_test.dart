import 'package:ccrlogger/ui/theme/color_math.dart';
import 'package:ccrlogger/ui/theme/omarchy/catppuccin.dart';
import 'package:ccrlogger/ui/theme/omarchy/ethereal.dart';
import 'package:ccrlogger/ui/theme/omarchy/hackerman.dart';
import 'package:ccrlogger/ui/theme/omarchy/miasma.dart';
import 'package:ccrlogger/ui/theme/omarchy/omarchy_colors.dart';
import 'package:ccrlogger/ui/theme/omarchy/omarchy_mapping.dart';
import 'package:ccrlogger/ui/theme/omarchy/retro_82.dart';
import 'package:ccrlogger/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _sources = <String, OmarchyColors>{
  'ethereal': etherealColors,
  'retro82': retro82Colors,
  'catppuccin': catppuccinColors,
  'hackerman': hackermanColors,
  'miasma': miasmaColors,
};

void main() {
  group('direct mappings', () {
    test(
      'Catppuccin surfaces, text and accent come straight from the source',
      () {
        final p = paletteFromOmarchy(catppuccinColors);
        expect(p.surfaceBg, const Color(0xFF1E1E2E));
        expect(p.surfaceCard, const Color(0xFF313244));
        expect(p.surfaceRaised, const Color(0xFF45475A));
        expect(p.surfaceBezel, const Color(0xFF585B70));
        expect(p.textPrimary, const Color(0xFFCDD6F4));
        expect(p.textSecondary, const Color(0xFFBAC2DE));
        expect(p.textInverse, const Color(0xFF1E1E2E));
        expect(p.accentPrimary, const Color(0xFF89B4FA));
        expect(p.chartTraceDepth, p.textPrimary);
        expect(p.chartTraceSetpoint, p.textSecondary);
      },
    );

    test('every theme maps background, card and accent from its source', () {
      _sources.forEach((name, o) {
        final p = paletteFromOmarchy(o);
        expect(p.surfaceBg, o.background, reason: name);
        expect(p.surfaceCard, o.lighterBackground, reason: name);
        expect(p.accentPrimary, o.accent, reason: name);
        expect(p.textPrimary, o.foreground, reason: name);
      });
    });

    test('derived tokens lie between their endpoints', () {
      final p = paletteFromOmarchy(etherealColors);
      expect(
        p.accentMuted,
        Color.lerp(etherealColors.accent, etherealColors.background, 0.5),
      );
      expect(
        p.chartGrid,
        Color.lerp(
          etherealColors.lighterBackground,
          etherealColors.selection,
          0.5,
        ),
      );
    });
  });

  group('readability floor', () {
    test('liftToContrast leaves a passing colour untouched', () {
      const c = Color(0xFFCDD6F4);
      expect(
        liftToContrast(c, const Color(0xFFFFFFFF), const [
          Color(0xFF1E1E2E),
        ], 4.5),
        c,
      );
    });

    test('liftToContrast raises a failing colour until it passes', () {
      const dim = Color(0xFF555555);
      const bgs = [Color(0xFF222222), Color(0xFF2C2C2C)];
      final lifted = liftToContrast(dim, const Color(0xFFC2C2B0), bgs, 3.0);
      expect(lifted, isNot(dim));
      for (final bg in bgs) {
        expect(contrastRatio(lifted, bg), greaterThanOrEqualTo(3.0));
      }
    });

    test('Miasma muted and secondary text are lifted, primary is not', () {
      final p = paletteFromOmarchy(miasmaColors);
      expect(p.textPrimary, miasmaColors.foreground);
      expect(p.textSecondary, isNot(miasmaColors.lightForeground));
      expect(p.textMuted, isNot(miasmaColors.darkForeground));
    });

    test('Ethereal text needs no lifting', () {
      final p = paletteFromOmarchy(etherealColors);
      expect(p.textSecondary, etherealColors.lightForeground);
      expect(p.textMuted, etherealColors.darkForeground);
    });

    test('every theme meets the text contrast floors', () {
      _sources.forEach((name, o) {
        final p = paletteFromOmarchy(o);
        for (final bg in [p.surfaceBg, p.surfaceCard]) {
          expect(
            contrastRatio(p.textPrimary, bg),
            greaterThanOrEqualTo(kMinTextContrast),
            reason: '$name textPrimary',
          );
          expect(
            contrastRatio(p.textSecondary, bg),
            greaterThanOrEqualTo(kMinTextContrast),
            reason: '$name textSecondary',
          );
          expect(
            contrastRatio(p.textMuted, bg),
            greaterThanOrEqualTo(kMinMutedTextContrast),
            reason: '$name textMuted',
          );
        }
      });
    });
  });

  group('cells and PPO2', () {
    test('stated choices are the ones the rules allow', () {
      _sources.forEach((name, o) {
        final card = o.lighterBackground;
        expect(
          o.useOwnCellColors,
          cellColorsPass(o.green, o.blue, o.magenta, card),
          reason: '$name useOwnCellColors',
        );
        final p = paletteFromOmarchy(o);
        expect(
          o.useOwnPpo2Color,
          ppo2ColorPasses(
            o.yellow,
            p.chartTraceDepth,
            p.chartTraceSetpoint,
            card,
            [p.cell1, p.cell2, p.cell3],
          ),
          reason: '$name useOwnPpo2Color',
        );
      });
    });

    test('expected outcome per theme', () {
      expect(etherealColors.useOwnCellColors, isTrue);
      expect(catppuccinColors.useOwnCellColors, isTrue);
      expect(retro82Colors.useOwnCellColors, isFalse);
      expect(hackermanColors.useOwnCellColors, isFalse);
      expect(miasmaColors.useOwnCellColors, isFalse);
      expect(etherealColors.useOwnPpo2Color, isTrue);
      expect(retro82Colors.useOwnPpo2Color, isTrue);
      expect(catppuccinColors.useOwnPpo2Color, isTrue);
      expect(miasmaColors.useOwnPpo2Color, isTrue);
      expect(hackermanColors.useOwnPpo2Color, isFalse);
    });

    test('own cell colours are used when stated, Wreck defaults otherwise', () {
      final cat = paletteFromOmarchy(catppuccinColors);
      expect(cat.cell1, catppuccinColors.green);
      expect(cat.cell2, catppuccinColors.blue);
      expect(cat.cell3, catppuccinColors.magenta);

      final hack = paletteFromOmarchy(hackermanColors);
      expect(hack.cell1, AppColors.wreck.cell1);
      expect(hack.cell2, AppColors.wreck.cell2);
      expect(hack.cell3, AppColors.wreck.cell3);
      expect(hack.chartTracePpo2, AppColors.wreck.chartTracePpo2);
      expect(paletteFromOmarchy(retro82Colors).chartTracePpo2,
          retro82Colors.yellow);
    });
  });
}
