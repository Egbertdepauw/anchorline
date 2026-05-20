import 'package:ccrlogger/data/db/dive_plans_dao.dart';
import 'package:ccrlogger/ui/widgets/saved_plans_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders saved plans with name + last-modified', (tester) async {
    final plans = [
      SavedDivePlan(
        id: 'p1',
        name: 'Cave dive 60m',
        updatedAt: DateTime(2026, 5, 19, 14, 30),
        mode: DivePlanMode.cc,
      ),
      SavedDivePlan(
        id: 'p2',
        name: 'Reef 30m',
        updatedAt: DateTime(2026, 5, 18, 10),
        mode: DivePlanMode.cc,
      ),
    ];
    String? loaded;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SavedPlansSheet(
          plans: plans,
          onLoad: (id) => loaded = id,
          onDelete: (_) {},
        ),
      ),
    ));
    expect(find.text('Cave dive 60m'), findsOneWidget);
    expect(find.text('Reef 30m'), findsOneWidget);
    await tester.tap(find.text('Cave dive 60m'));
    expect(loaded, 'p1');
  });
}
