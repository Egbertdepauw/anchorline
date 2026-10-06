import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:ccrlogger/ui/theme/safety_colors.dart';
import 'package:ccrlogger/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppTheme.dark uses wreck palette', () {
    final t = AppTheme.dark();
    expect(t.colorScheme.surface, AppColors.wreck.surfaceBg);
    expect(t.colorScheme.primary, AppColors.wreck.accentPrimary);
    expect(t.colorScheme.error, SafetyColors.danger);
    expect(t.scaffoldBackgroundColor, AppColors.wreck.surfaceBg);
  });

  test('AppTheme.dark TextTheme body uses Inter', () {
    final t = AppTheme.dark();
    expect(t.textTheme.bodyMedium?.fontFamily, 'Inter');
    expect(t.textTheme.titleLarge?.fontFamily, 'Inter');
  });

  test('AppTheme.dark card radius is hard-edge (2px)', () {
    final t = AppTheme.dark();
    final shape = t.cardTheme.shape as RoundedRectangleBorder?;
    final radius = (shape?.borderRadius as BorderRadius?)?.topLeft;
    expect(radius, const Radius.circular(2));
  });
}
