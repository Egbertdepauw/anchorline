import 'package:ccrlogger/ui/notifiers/dive_detail_notifier.dart';
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
}
