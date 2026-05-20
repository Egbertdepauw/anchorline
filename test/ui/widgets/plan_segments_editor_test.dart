import 'package:ccrlogger/data/models/dive_plan.dart';
import 'package:ccrlogger/ui/widgets/plan_segments_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('add segment defaults to deepest existing depth + 10 m / 10 min',
      (tester) async {
    DivePlanSegment? added;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanSegmentsEditor(
          gases: const [
            DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
          ],
          segments: const [
            DivePlanSegment(
                depthMeters: 30,
                durationMinutes: 20,
                gasMixIndex: 0,
                setpoint: 1.3),
          ],
          onAdd: (s) => added = s,
          onRemove: (_) {},
          onReplace: (_, _) {},
          onReorder: (_, _) {},
          mode: DivePlanMode.cc,
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('add-segment')));
    expect(added!.depthMeters, 40);
    expect(added!.durationMinutes, 10);
  });

  testWidgets('segment row exposes depth + time + gas + setpoint as inputs',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanSegmentsEditor(
          gases: const [
            DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
          ],
          segments: const [
            DivePlanSegment(
                depthMeters: 50,
                durationMinutes: 20,
                gasMixIndex: 0,
                setpoint: 1.3),
          ],
          onAdd: (_) {},
          onRemove: (_) {},
          onReplace: (_, _) {},
          onReorder: (_, _) {},
          mode: DivePlanMode.cc,
        ),
      ),
    ));
    // Depth + time render as editable TextFields with their current value.
    final depthField = tester.widget<TextField>(find.byType(TextField).at(0));
    final timeField = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(depthField.controller!.text, '50');
    expect(timeField.controller!.text, '20');
    // Gas dropdown shows the gas label.
    expect(find.text('Tx21/35'), findsWidgets);
    // Setpoint dropdown shows the active value.
    expect(find.text('1.3'), findsWidgets);
  });

  testWidgets('editing depth fires onReplace with the new value',
      (tester) async {
    DivePlanSegment? replaced;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanSegmentsEditor(
          gases: const [
            DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
          ],
          segments: const [
            DivePlanSegment(
                depthMeters: 50,
                durationMinutes: 20,
                gasMixIndex: 0,
                setpoint: 1.3),
          ],
          onAdd: (_) {},
          onRemove: (_) {},
          onReplace: (_, s) => replaced = s,
          onReorder: (_, _) {},
          mode: DivePlanMode.cc,
        ),
      ),
    ));
    await tester.enterText(find.byType(TextField).at(0), '45');
    await tester.pump();
    expect(replaced!.depthMeters, 45);
  });

  testWidgets(
      'gas dropdown hides gases whose OC PPO2 exceeds 1.61 at the row depth',
      (tester) async {
    // 60 m on EAN 50: PPO₂ ≈ 0.50 × 7.013 ≈ 3.5 — way over the cap.
    // The dropdown should drop EAN 50 from its items. Tx 18/45 (deep
    // diluent) and the currently-selected gas (index 0 — Tx 18/45)
    // must stay.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanSegmentsEditor(
          gases: const [
            DivePlanGas(oxygenPercent: 18, heliumPercent: 45, isDiluent: true),
            DivePlanGas(oxygenPercent: 50, heliumPercent: 0, isDiluent: false),
            DivePlanGas(oxygenPercent: 100, heliumPercent: 0, isDiluent: false),
          ],
          segments: const [
            DivePlanSegment(
                depthMeters: 60,
                durationMinutes: 20,
                gasMixIndex: 0,
                setpoint: 1.3),
          ],
          onAdd: (_) {},
          onRemove: (_) {},
          onReplace: (_, _) {},
          onReorder: (_, _) {},
          mode: DivePlanMode.cc,
        ),
      ),
    ));
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    // Tx 18/45 is the selection — present.
    expect(find.text('Tx18/45'), findsWidgets);
    // EAN 50 and pure O2 must be HIDDEN at 60 m.
    expect(find.text('EAN50'), findsNothing);
    expect(find.text('EAN100'), findsNothing);
  });

  testWidgets('segment row shows a red warning line when chosen gas '
      'OC PPO2 exceeds 1.51 at the row depth', (tester) async {
    // EAN 32 at 50 m: PPO₂ = 0.32 × (1.013 + 5) ≈ 1.92 → unsafe red.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanSegmentsEditor(
          gases: const [
            DivePlanGas(oxygenPercent: 32, heliumPercent: 0, isDiluent: true),
          ],
          segments: const [
            DivePlanSegment(
                depthMeters: 50,
                durationMinutes: 20,
                gasMixIndex: 0,
                setpoint: 1.3),
          ],
          onAdd: (_) {},
          onRemove: (_) {},
          onReplace: (_, _) {},
          onReorder: (_, _) {},
          mode: DivePlanMode.cc,
        ),
      ),
    ));
    // Warning text appears below the row when the chosen gas is unsafe.
    expect(find.textContaining('PPO₂'), findsWidgets);
    expect(find.textContaining('1.51'), findsWidgets);
  });

  testWidgets('editing time fires onReplace; 0 = instant switch',
      (tester) async {
    DivePlanSegment? replaced;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanSegmentsEditor(
          gases: const [
            DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
          ],
          segments: const [
            DivePlanSegment(
                depthMeters: 50,
                durationMinutes: 20,
                gasMixIndex: 0,
                setpoint: 1.3),
          ],
          onAdd: (_) {},
          onRemove: (_) {},
          onReplace: (_, s) => replaced = s,
          onReorder: (_, _) {},
          mode: DivePlanMode.cc,
        ),
      ),
    ));
    await tester.enterText(find.byType(TextField).at(1), '0');
    await tester.pump();
    expect(replaced!.durationMinutes, 0);
  });
}
