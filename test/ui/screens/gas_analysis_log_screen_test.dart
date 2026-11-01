import 'package:ccrlogger/data/db/gas_analyses_dao.dart';
import 'package:ccrlogger/ui/screens/gas_analysis_log_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/fake_gas_analyses_dao.dart';

void main() {
  GasAnalysis entry(String id, DateTime at, double o2, double he,
          {String? cylinderId, String? label, bool stable = true}) =>
      GasAnalysis(
        id: id,
        cylinderId: cylinderId,
        cylinderLabel: label,
        analysedBy: 'Egbert',
        analysedAt: at,
        o2Percent: o2,
        hePercent: he,
        fillPressureBar: 200,
        stable: stable,
      );

  FakeGasAnalysesDao seeded() => FakeGasAnalysesDao(analyses: [
        entry('old', DateTime(2026, 9, 1, 10), 32.2, 0,
            cylinderId: 'c1', label: 'S80 left'),
        entry('new', DateTime(2026, 10, 30, 18, 5), 21.4, 34.6,
            cylinderId: 'c2', label: 'AL40 deco', stable: false),
      ]);

  Future<void> pump(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();
  }

  testWidgets('lists newest first with whole-number mix names',
      (tester) async {
    await pump(tester, GasAnalysisLogScreen(dao: seeded()));
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title as Text).data)
        .toList();
    expect(titles, ['Tx21/35', 'EAN32']);
    expect(find.textContaining('AL40 deco'), findsOneWidget);
    expect(find.textContaining('Egbert'), findsNWidgets(2));
    expect(find.textContaining('200 bar'), findsNWidgets(2));
    // Stable flag: one warning (not stable), one check.
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('per-cylinder view filters and titles by cylinder',
      (tester) async {
    await pump(
        tester,
        GasAnalysisLogScreen(
            dao: seeded(), cylinderId: 'c1', cylinderLabel: 'S80 left'));
    expect(find.text('Analyses · S80 left'), findsOneWidget);
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('EAN32'), findsOneWidget);
  });

  testWidgets('swipe soft-deletes through the DAO', (tester) async {
    final dao = seeded();
    await pump(tester, GasAnalysisLogScreen(dao: dao));
    await tester.drag(find.text('Tx21/35'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(dao.deleted, ['new']);
    expect(find.text('Tx21/35'), findsNothing);
    expect(find.text('EAN32'), findsOneWidget);
    expect(find.text('Deleted Tx21/35 analysis.'), findsOneWidget);
  });

  testWidgets('export hands the CSV of the shown entries to the sharer',
      (tester) async {
    String? csv;
    String? name;
    await pump(
        tester,
        GasAnalysisLogScreen(
          dao: seeded(),
          shareCsv: (c, n, _) async {
            csv = c;
            name = n;
          },
        ));
    await tester.tap(find.byKey(const ValueKey('analysis-log-export')));
    await tester.pumpAndSettle();
    expect(name, matches(RegExp(r'^gas-analyses-\d{4}-\d{2}-\d{2}\.csv$')));
    final lines = csv!.trimRight().split('\n');
    expect(lines.first, startsWith('"time","cylinder","diver","mix"'));
    expect(lines, hasLength(3));
    expect(lines[1], contains('"AL40 deco","Egbert","Tx21/35"'));
    expect(lines[1], endsWith('"false","","bailout"'));
  });

  testWidgets('empty log: message and export disabled', (tester) async {
    await pump(tester, GasAnalysisLogScreen(dao: FakeGasAnalysesDao()));
    expect(find.textContaining('No analyses saved yet'), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(
                find.byKey(const ValueKey('analysis-log-export')))
            .onPressed,
        isNull);
  });

  testWidgets('a save elsewhere refreshes the list', (tester) async {
    final dao = FakeGasAnalysesDao();
    await pump(tester, GasAnalysisLogScreen(dao: dao));
    await dao.add(NewGasAnalysis(
      analysedAt: DateTime(2026, 10, 31),
      o2Percent: 50.3,
      hePercent: 0,
      stable: true,
    ));
    await tester.pumpAndSettle();
    expect(find.text('EAN50'), findsOneWidget);
  });
}
