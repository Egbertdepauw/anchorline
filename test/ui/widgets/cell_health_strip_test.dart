import 'package:ccrlogger/analysis/cell_health.dart';
import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:ccrlogger/ui/theme/safety_colors.dart';
import 'package:ccrlogger/ui/widgets/cell_health_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(CellHealth h) => MaterialApp(
        theme: AppThemes.byId('catppuccin').themeData,
        home: Scaffold(body: CellHealthStrip(health: h, slot: 1)),
      );

  CellHealth health(double months, CellMvStatus s) => CellHealth(
        ageMonths: months,
        diveCount: 10,
        mvStatus: s,
        baselinePeakMv: 50,
        recentPeakMv: 50,
      );

  Color barColor(WidgetTester tester) {
    final bar = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    return (bar.valueColor! as AlwaysStoppedAnimation<Color>).value;
  }

  Color pillBorder(WidgetTester tester) {
    final box = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.border != null);
    return (box.border! as Border).top.color;
  }

  for (final c in <(String, double, CellMvStatus, Color)>[
    ('healthy', 5, CellMvStatus.healthy, SafetyColors.success),
    ('watch', 10, CellMvStatus.watch, SafetyColors.warning),
    ('replace', 13, CellMvStatus.replace, SafetyColors.danger),
  ]) {
    testWidgets('${c.$1} cell renders the safety colour on a non-default theme',
        (tester) async {
      await tester.pumpWidget(wrap(health(c.$2, c.$3)));
      expect(barColor(tester), c.$4);
      expect(pillBorder(tester), c.$4.withValues(alpha: 0.5));
    });
  }

  testWidgets('insufficient data pill uses the theme muted text colour',
      (tester) async {
    final t = AppThemes.byId('catppuccin');
    await tester.pumpWidget(
        wrap(health(5, CellMvStatus.insufficientData)));
    expect(pillBorder(tester), t.palette.textMuted.withValues(alpha: 0.5));
  });
}
