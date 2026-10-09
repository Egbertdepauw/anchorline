import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:ccrlogger/ui/theme/data_colors.dart';
import 'package:ccrlogger/ui/theme/safety_colors.dart';
import 'package:ccrlogger/ui/theme/tokens.dart';
import 'package:ccrlogger/ui/widgets/trace_segmented_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each legend swatch is the colour the chart draws that trace in', () {
    for (final t in AppThemes.all) {
      final p = t.palette;
      expect(traceLegendColor(TraceType.ppo2, p), p.chartTracePpo2,
          reason: t.id);
      expect(traceLegendColor(TraceType.setpoint, p), p.chartTraceSetpoint,
          reason: t.id);
      expect(traceLegendColor(TraceType.cells, p), p.cell1, reason: t.id);
      expect(traceLegendColor(TraceType.deco, p), SafetyColors.warning);
      expect(traceLegendColor(TraceType.gasChanges, p), SafetyColors.info);
      expect(traceLegendColor(TraceType.tanks, p), DataColors.tanks.first);
      expect(traceLegendColor(TraceType.gf99, p), DataColors.gf99);
      expect(traceLegendColor(TraceType.ceiling, p), DataColors.ceiling);
      expect(traceLegendColor(TraceType.waterTemp, p), DataColors.waterTemp);
      expect(traceLegendColor(TraceType.density, p), p.textPrimary,
          reason: t.id);
      expect(traceLegendColor(TraceType.end, p), p.textPrimary, reason: t.id);
    }
  });

  test('every trace type has a legend colour', () {
    for (final type in TraceType.values) {
      expect(() => traceLegendColor(type, AppColors.wreck), returnsNormally);
    }
  });

  // `NoSplash.splashFactory` skips the ink-ripple animation, which
  // otherwise tries to load `shaders/ink_sparkle.frag` and trips a
  // Flutter 3.44 shader-version mismatch in the test harness. None of
  // these tests verify the ripple itself.
  Widget wrap(Widget child) => MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(body: child),
      );

  testWidgets('TraceSegmentedBar renders all segments with their labels',
      (tester) async {
    await tester.pumpWidget(wrap(TraceSegmentedBar(
      visibleTraces: const {TraceType.ppo2, TraceType.deco},
      onToggle: (_) {},
    )));
    expect(find.text('PPO2'), findsOneWidget);
    expect(find.text('Setpoint'), findsOneWidget);
    expect(find.text('Cells'), findsOneWidget);
    expect(find.text('Deco'), findsOneWidget);
    expect(find.text('Tanks'), findsOneWidget);
    expect(find.text('Gas'), findsOneWidget);
    expect(find.text('Density'), findsOneWidget);
    expect(find.text('END'), findsOneWidget);
    expect(find.text('GF99'), findsOneWidget);
    expect(find.text('Ceiling'), findsOneWidget);
    // Issue #11: water-temperature trace.
    expect(find.text('Temp'), findsOneWidget);
  });

  testWidgets('tapping the Temp segment calls onToggle(waterTemp)',
      (tester) async {
    TraceType? toggled;
    await tester.pumpWidget(wrap(TraceSegmentedBar(
      visibleTraces: const {},
      onToggle: (t) => toggled = t,
    )));
    // Temp is the last segment and sits off the default 800 px viewport.
    await tester.scrollUntilVisible(find.text('Temp'), 50);
    await tester.tap(find.text('Temp'));
    expect(toggled, TraceType.waterTemp);
  });

  testWidgets('tapping an unselected segment calls onToggle with its TraceType',
      (tester) async {
    TraceType? toggled;
    await tester.pumpWidget(wrap(TraceSegmentedBar(
      visibleTraces: const {TraceType.ppo2},
      onToggle: (t) => toggled = t,
    )));
    await tester.tap(find.text('Cells'));
    expect(toggled, TraceType.cells);
  });

  testWidgets('tapping a selected segment calls onToggle with its TraceType',
      (tester) async {
    TraceType? toggled;
    await tester.pumpWidget(wrap(TraceSegmentedBar(
      visibleTraces: const {TraceType.ppo2},
      onToggle: (t) => toggled = t,
    )));
    await tester.tap(find.text('PPO2'));
    expect(toggled, TraceType.ppo2);
  });

  testWidgets('TraceSegmentedBar wraps its segments in a horizontal SingleChildScrollView',
      (tester) async {
    await tester.pumpWidget(wrap(TraceSegmentedBar(
      visibleTraces: const {},
      onToggle: (_) {},
    )));
    final scroll = tester.widget<SingleChildScrollView>(
      find.descendant(
        of: find.byType(TraceSegmentedBar),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(scroll.scrollDirection, Axis.horizontal);
  });

  testWidgets('tapping Density / END segments calls onToggle', (tester) async {
    TraceType? toggled;
    await tester.pumpWidget(wrap(TraceSegmentedBar(
      visibleTraces: const {},
      onToggle: (t) => toggled = t,
    )));
    await tester.tap(find.text('Density'));
    expect(toggled, TraceType.density);
    await tester.tap(find.text('END'));
    expect(toggled, TraceType.end);
  });

  testWidgets('tapping GF99 / Ceiling segments calls onToggle', (tester) async {
    TraceType? toggled;
    await tester.pumpWidget(wrap(TraceSegmentedBar(
      visibleTraces: const {},
      onToggle: (t) => toggled = t,
    )));
    await tester.tap(find.text('GF99'));
    expect(toggled, TraceType.gf99);
    // Ceiling is the last segment and may be off-screen in the default
    // 800 px test viewport — scroll to it before tapping.
    await tester.scrollUntilVisible(find.text('Ceiling'), 50);
    await tester.tap(find.text('Ceiling'));
    expect(toggled, TraceType.ceiling);
  });

  testWidgets(
      'TraceSegmentedBar does not overflow at iPhone-portrait width (375 px)',
      (tester) async {
    tester.view.physicalSize = const Size(375, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(wrap(TraceSegmentedBar(
      visibleTraces: const {
        TraceType.ppo2,
        TraceType.setpoint,
        TraceType.cells,
        TraceType.deco,
        TraceType.tanks,
        TraceType.gasChanges,
      },
      onToggle: (_) {},
    )));
    expect(tester.takeException(), isNull);
  });
}
