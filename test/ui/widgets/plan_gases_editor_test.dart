import 'package:ccrlogger/data/models/dive_plan.dart';
import 'package:ccrlogger/ui/widgets/plan_gases_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('add gas → onAdd called with default 21/0 diluent',
      (tester) async {
    DivePlanGas? added;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanGasesEditor(
          gases: const [],
          onAdd: (g) => added = g,
          onRemove: (_) {},
          onReplace: (_, _) {},
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('add-gas')));
    expect(added,
        const DivePlanGas(oxygenPercent: 21, heliumPercent: 0, isDiluent: true));
  });

  testWidgets('rows render existing gases', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanGasesEditor(
          gases: const [
            DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
            DivePlanGas(oxygenPercent: 50, heliumPercent: 0, isDiluent: false),
          ],
          onAdd: (_) {},
          onRemove: (_) {},
          onReplace: (_, _) {},
        ),
      ),
    ));
    expect(find.text('Tx21/35'), findsOneWidget);
    expect(find.text('EAN50'), findsOneWidget);
  });
}
