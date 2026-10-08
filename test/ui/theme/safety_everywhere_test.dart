import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:ccrlogger/ui/theme/gf_color.dart';
import 'package:ccrlogger/ui/theme/safety_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('safety colours are the same under every theme',
      (tester) async {
    for (final t in AppThemes.all) {
      late Color error;
      await tester.pumpWidget(MaterialApp(
        theme: t.themeData,
        home: Builder(builder: (context) {
          error = Theme.of(context).colorScheme.error;
          return const SizedBox();
        }),
      ));
      expect(error, SafetyColors.danger, reason: t.id);
      expect(gfBandColor(50), SafetyColors.gfWithinLimits, reason: t.id);
      expect(gfBandColor(90), SafetyColors.gfOverHigh, reason: t.id);
      expect(gfBandColor(120), SafetyColors.gfOverLimit, reason: t.id);
    }
  });
}
