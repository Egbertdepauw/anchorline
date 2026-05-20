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

  testWidgets('rows expose O2 + He as editable TextFields seeded with the gas',
      (tester) async {
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
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList(growable: false);
    // 2 rows × 2 fields each = 4 TextFields.
    expect(fields.length, 4);
    expect(fields[0].controller!.text, '21');
    expect(fields[1].controller!.text, '35');
    expect(fields[2].controller!.text, '50');
    expect(fields[3].controller!.text, '0');
  });

  testWidgets('editing O2 fires onReplace with the new oxygen percent',
      (tester) async {
    DivePlanGas? replaced;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanGasesEditor(
          gases: const [
            DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
          ],
          onAdd: (_) {},
          onRemove: (_) {},
          onReplace: (_, g) => replaced = g,
        ),
      ),
    ));
    await tester.enterText(find.byType(TextField).at(0), '18');
    await tester.pump();
    expect(replaced!.oxygenPercent, 18);
    expect(replaced!.heliumPercent, 35);
    expect(replaced!.isDiluent, isTrue);
  });

  testWidgets('editing He fires onReplace with the new helium percent',
      (tester) async {
    DivePlanGas? replaced;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanGasesEditor(
          gases: const [
            DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
          ],
          onAdd: (_) {},
          onRemove: (_) {},
          onReplace: (_, g) => replaced = g,
        ),
      ),
    ));
    await tester.enterText(find.byType(TextField).at(1), '45');
    await tester.pump();
    expect(replaced!.heliumPercent, 45);
  });
}
