import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:ccrlogger/ui/theme/color_math.dart';
import 'package:ccrlogger/ui/theme/omarchy/omarchy_mapping.dart';
import 'package:ccrlogger/ui/theme/safety_colors.dart';
import 'package:ccrlogger/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Safety colours known to fall short of 3:1 on a theme's card. See the
/// spec, "Known contrast shortfall". Keys are `<themeId>/<safetyName>`.
const _knownCardShortfalls = {
  'catppuccin/gfOverLimit',
  'miasma/gfOverLimit',
};

void main() {
  group('registry', () {
    test('lists the six themes, Wreck first', () {
      expect(AppThemes.all.map((t) => t.id), [
        'wreck',
        'ethereal',
        'retro82',
        'catppuccin',
        'hackerman',
        'miasma',
      ]);
      expect(AppThemes.all.map((t) => t.name), [
        'Wreck',
        'Ethereal',
        'Retro 82',
        'Catppuccin',
        'Hackerman',
        'Miasma',
      ]);
    });

    test('ids are unique', () {
      final ids = AppThemes.all.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('byId finds a theme and falls back to Wreck', () {
      expect(AppThemes.byId('miasma').name, 'Miasma');
      expect(AppThemes.byId(null).id, 'wreck');
      expect(AppThemes.byId('no-such-theme').id, 'wreck');
      expect(AppThemes.byId('').id, 'wreck');
      expect(AppThemes.defaultId, 'wreck');
    });

    test('Wreck is unchanged', () {
      final w = AppThemes.byId('wreck').palette;
      expect(w, same(AppColors.wreck));
      expect(w.surfaceBg, const Color(0xFF0A1518));
      expect(w.surfaceCard, const Color(0xFF142028));
      expect(w.surfaceRaised, const Color(0xFF1F2E38));
      expect(w.surfaceBezel, const Color(0xFF2A3A45));
      expect(w.textPrimary, const Color(0xFFE0E8EC));
      expect(w.textSecondary, const Color(0xFFA0AEB6));
      expect(w.textMuted, const Color(0xFF6B7D88));
      expect(w.textInverse, const Color(0xFF0A1518));
      expect(w.accentPrimary, const Color(0xFFC97B3A));
      expect(w.accentMuted, const Color(0xFF806633));
      expect(w.cell1, const Color(0xFF4ADE80));
      expect(w.cell2, const Color(0xFF60A5FA));
      expect(w.cell3, const Color(0xFFF472B6));
      expect(w.chartGrid, const Color(0xFF1A2832));
      expect(w.chartTraceDepth, const Color(0xFFE0E8EC));
      expect(w.chartTracePpo2, const Color(0xFFFFCC66));
      expect(w.chartTraceSetpoint, const Color(0xFFA0AEB6));
    });

    test('themeData carries the palette and is built once', () {
      final t = AppThemes.byId('catppuccin');
      expect(t.themeData.extension<ThemePalette>(), same(t.palette));
      expect(t.themeData, same(t.themeData));
      expect(t.themeData.brightness, Brightness.dark);
    });
  });

  group('every registered theme', () {
    test('meets the text contrast floors', () {
      for (final t in AppThemes.all) {
        final p = t.palette;
        for (final bg in [p.surfaceBg, p.surfaceCard]) {
          expect(contrastRatio(p.textPrimary, bg),
              greaterThanOrEqualTo(kMinTextContrast),
              reason: '${t.id} textPrimary');
          expect(contrastRatio(p.textSecondary, bg),
              greaterThanOrEqualTo(kMinTextContrast),
              reason: '${t.id} textSecondary');
          expect(contrastRatio(p.textMuted, bg),
              greaterThanOrEqualTo(kMinMutedTextContrast),
              reason: '${t.id} textMuted');
        }
      }
    });

    test('ends up with cell and PPO2 colours that pass the rules', () {
      for (final t in AppThemes.all) {
        final p = t.palette;
        expect(cellColorsPass(p.cell1, p.cell2, p.cell3, p.surfaceCard),
            isTrue,
            reason: '${t.id} cells');
        expect(
            ppo2ColorPasses(p.chartTracePpo2, p.chartTraceDepth,
                p.chartTraceSetpoint, p.surfaceCard, [p.cell1, p.cell2, p.cell3]),
            isTrue,
            reason: '${t.id} ppo2');
      }
    });

    test('shows every safety colour readably on its background', () {
      for (final t in AppThemes.all) {
        SafetyColors.all.forEach((name, color) {
          expect(contrastRatio(color, t.palette.surfaceBg),
              greaterThanOrEqualTo(3.0),
              reason: '${t.id}/$name on background');
        });
      }
    });

    test('shows every safety colour readably on its card, bar known cases',
        () {
      for (final t in AppThemes.all) {
        SafetyColors.all.forEach((name, color) {
          final ratio = contrastRatio(color, t.palette.surfaceCard);
          final key = '${t.id}/$name';
          if (_knownCardShortfalls.contains(key)) {
            expect(ratio, greaterThanOrEqualTo(2.5), reason: '$key floor');
            expect(ratio, lessThan(3.0),
                reason: '$key no longer falls short: remove it from '
                    '_knownCardShortfalls');
          } else {
            expect(ratio, greaterThanOrEqualTo(3.0), reason: '$key on card');
          }
        });
      }
    });
  });
}
