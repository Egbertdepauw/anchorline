import 'package:ccrlogger/ui/widgets/trace_segmented_bar.dart' show TraceType;
import 'package:ccrlogger/ui/widgets/trace_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows all 5 trace chips', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TraceToggleChips(
                visibleTraces: {
                  TraceType.ppo2,
                  TraceType.setpoint,
                  TraceType.deco
                },
                onToggle: (_) {}))));
    expect(find.text('PPO2'), findsOneWidget);
    expect(find.text('Setpoint'), findsOneWidget);
    expect(find.text('Cells'), findsOneWidget);
    expect(find.text('Deco'), findsOneWidget);
    expect(find.text('Tanks'), findsOneWidget);
  });

  testWidgets('tapping a chip calls onToggle', (tester) async {
    TraceType? toggled;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TraceToggleChips(
                visibleTraces: {TraceType.ppo2},
                onToggle: (t) => toggled = t))));
    await tester.tap(find.text('Cells'));
    expect(toggled, equals(TraceType.cells));
  });

  testWidgets('wraps without overflow at iPhone-narrow width', (tester) async {
    tester.view.physicalSize = const Size(375, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TraceToggleChips(
                visibleTraces: const {
                  TraceType.ppo2,
                  TraceType.setpoint,
                  TraceType.deco,
                },
                onToggle: (_) {}))));
    expect(tester.takeException(), isNull);
    expect(find.byType(Wrap), findsOneWidget);
    expect(find.text('PPO2'), findsOneWidget);
    expect(find.text('Tanks'), findsOneWidget);
  });
}
