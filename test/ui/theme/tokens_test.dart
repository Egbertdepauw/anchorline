import 'package:ccrlogger/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppColors.wreck', () {
    test('surface.bg matches spec', () {
      expect(AppColors.wreck.surfaceBg, const Color(0xFF0A1518));
    });
    test('accent.primary is Anchorline reel-orange', () {
      expect(AppColors.wreck.accentPrimary, const Color(0xFFC97B3A));
    });
    test('cell colours are locked', () {
      expect(AppColors.wreck.cell1, const Color(0xFF4ADE80));
      expect(AppColors.wreck.cell2, const Color(0xFF60A5FA));
      expect(AppColors.wreck.cell3, const Color(0xFFF472B6));
    });
  });

  group('Spacing', () {
    test('scale is 4/8/12/16/24/32/48', () {
      expect(Spacing.xs, 4);
      expect(Spacing.sm, 8);
      expect(Spacing.md, 12);
      expect(Spacing.lg, 16);
      expect(Spacing.xl, 24);
      expect(Spacing.xxl, 32);
      expect(Spacing.xxxl, 48);
    });
  });

  group('Radii', () {
    test('hard-edge defaults are 2px', () {
      expect(Radii.card, const Radius.circular(2));
      expect(Radii.button, const Radius.circular(2));
      expect(Radii.chip, const Radius.circular(2));
      expect(Radii.modal, const Radius.circular(4));
    });
  });

  group('AppTypography', () {
    test('readouts use tabular figures', () {
      final readout = AppTypography.readoutMd;
      expect(readout.fontFamily, 'JetBrainsMono');
      final hasTabular =
          (readout.fontFeatures ?? []).any((f) => f.feature == 'tnum');
      expect(hasTabular, isTrue);
    });
    test('body uses Inter', () {
      expect(AppTypography.body.fontFamily, 'Inter');
    });
  });
}
