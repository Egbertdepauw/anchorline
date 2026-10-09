import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:ccrlogger/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final other = AppColors.wreck.copyWith(
    surfaceBg: const Color(0xFF1E1E2E),
    accentPrimary: const Color(0xFF89B4FA),
  );

  group('ThemePalette', () {
    test('copyWith replaces only the named fields', () {
      expect(other.surfaceBg, const Color(0xFF1E1E2E));
      expect(other.accentPrimary, const Color(0xFF89B4FA));
      expect(other.surfaceCard, AppColors.wreck.surfaceCard);
      expect(other.cell3, AppColors.wreck.cell3);
    });

    test('lerp returns the endpoints at t=0 and t=1', () {
      expect(AppColors.wreck.lerp(other, 0).surfaceBg,
          AppColors.wreck.surfaceBg);
      expect(AppColors.wreck.lerp(other, 1).surfaceBg, other.surfaceBg);
      expect(AppColors.wreck.lerp(other, 1).accentPrimary,
          other.accentPrimary);
    });

    test('lerp at t=1 returns every field of the other palette', () {
      const b = ThemePalette(
        surfaceBg: Color(0xFF000001),
        surfaceCard: Color(0xFF000002),
        surfaceRaised: Color(0xFF000003),
        surfaceBezel: Color(0xFF000004),
        textPrimary: Color(0xFF000005),
        textSecondary: Color(0xFF000006),
        textMuted: Color(0xFF000007),
        textInverse: Color(0xFF000008),
        accentPrimary: Color(0xFF000009),
        accentMuted: Color(0xFF00000A),
        cell1: Color(0xFF00000B),
        cell2: Color(0xFF00000C),
        cell3: Color(0xFF00000D),
        chartGrid: Color(0xFF00000E),
        chartTraceDepth: Color(0xFF00000F),
        chartTracePpo2: Color(0xFF000010),
        chartTraceSetpoint: Color(0xFF000011),
      );
      final r = AppColors.wreck.lerp(b, 1);
      expect(r.surfaceBg, b.surfaceBg);
      expect(r.surfaceCard, b.surfaceCard);
      expect(r.surfaceRaised, b.surfaceRaised);
      expect(r.surfaceBezel, b.surfaceBezel);
      expect(r.textPrimary, b.textPrimary);
      expect(r.textSecondary, b.textSecondary);
      expect(r.textMuted, b.textMuted);
      expect(r.textInverse, b.textInverse);
      expect(r.accentPrimary, b.accentPrimary);
      expect(r.accentMuted, b.accentMuted);
      expect(r.cell1, b.cell1);
      expect(r.cell2, b.cell2);
      expect(r.cell3, b.cell3);
      expect(r.chartGrid, b.chartGrid);
      expect(r.chartTraceDepth, b.chartTraceDepth);
      expect(r.chartTracePpo2, b.chartTracePpo2);
      expect(r.chartTraceSetpoint, b.chartTraceSetpoint);
    });

    test('lerp at t=0.5 is between the endpoints', () {
      final mid = AppColors.wreck.lerp(other, 0.5).surfaceBg;
      expect(mid, isNot(AppColors.wreck.surfaceBg));
      expect(mid, isNot(other.surfaceBg));
    });

    test('lerp with null returns this palette', () {
      expect(AppColors.wreck.lerp(null, 0.5), same(AppColors.wreck));
    });
  });

  group('context.palette', () {
    testWidgets('returns the palette of the active theme', (tester) async {
      late ThemePalette seen;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(other),
        home: Builder(builder: (context) {
          seen = context.palette;
          return const SizedBox();
        }),
      ));
      expect(seen.surfaceBg, const Color(0xFF1E1E2E));
    });

    testWidgets('falls back to Wreck when the theme carries no palette',
        (tester) async {
      late ThemePalette seen;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          seen = context.palette;
          return const SizedBox();
        }),
      ));
      expect(seen, same(AppColors.wreck));
    });
  });

  group('AppTheme.build', () {
    test('wires the palette into ThemeData', () {
      final t = AppTheme.build(other);
      expect(t.extension<ThemePalette>(), same(other));
      expect(t.colorScheme.surface, other.surfaceBg);
      expect(t.colorScheme.primary, other.accentPrimary);
      expect(t.scaffoldBackgroundColor, other.surfaceBg);
      expect(t.brightness, Brightness.dark);
    });

    test('dark() is build(wreck)', () {
      expect(AppTheme.dark().extension<ThemePalette>(),
          same(AppColors.wreck));
    });
  });
}
