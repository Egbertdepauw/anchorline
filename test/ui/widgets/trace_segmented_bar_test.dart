import 'package:ccrlogger/ui/widgets/trace_segmented_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: child));

  testWidgets('TraceSegmentedBar renders six segments with their labels',
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
}
