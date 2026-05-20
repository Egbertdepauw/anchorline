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

  testWidgets('segment row shows depth + time + gas label', (tester) async {
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
    expect(find.text('50 m'), findsOneWidget);
    expect(find.text('20 min'), findsOneWidget);
    expect(find.text('Tx21/35'), findsOneWidget);
  });
}
