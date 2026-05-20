import 'package:ccrlogger/data/models/dive_plan.dart';
import 'package:ccrlogger/ui/widgets/plan_bailout_bottles_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders existing bottles + add adds an AL40 @ 200 bar by default',
      (tester) async {
    DivePlanBailoutBottle? added;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanBailoutBottlesEditor(
          gases: const [
            DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
          ],
          bottles: const [
            DivePlanBailoutBottle(
                gasMixIndex: 0, waterCapacityL: 5.7, fillPressureBar: 200),
          ],
          onAdd: (b) => added = b,
          onRemove: (_) {},
          onReplace: (_, _) {},
        ),
      ),
    ));
    expect(find.textContaining('5.7'), findsWidgets);
    expect(find.textContaining('200'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('add-bottle')));
    expect(added!.waterCapacityL, 5.7);
    expect(added!.fillPressureBar, 200);
  });

  testWidgets('changing capacity field fires onReplace with the new value',
      (tester) async {
    DivePlanBailoutBottle? lastReplacement;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanBailoutBottlesEditor(
          gases: const [
            DivePlanGas(oxygenPercent: 21, heliumPercent: 0, isDiluent: false),
          ],
          bottles: const [
            DivePlanBailoutBottle(
                gasMixIndex: 0, waterCapacityL: 5.7, fillPressureBar: 200),
          ],
          onAdd: (_) {},
          onRemove: (_) {},
          onReplace: (_, b) => lastReplacement = b,
        ),
      ),
    ));
    await tester.enterText(find.byType(TextField).first, '11.1');
    expect(lastReplacement, isNotNull);
    expect(lastReplacement!.waterCapacityL, closeTo(11.1, 1e-9));
    expect(lastReplacement!.fillPressureBar, 200);
  });
}
