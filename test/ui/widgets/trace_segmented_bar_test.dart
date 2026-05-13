import 'package:ccrlogger/ui/widgets/trace_segmented_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: child));

  testWidgets('TraceSegmentedBar renders eight segments with their labels',
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
