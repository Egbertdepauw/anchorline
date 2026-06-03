import 'package:ccrlogger/ui/widgets/cell_mv_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final surface = <({DateTime date, double mv, String diveId})>[
    (date: DateTime(2025, 5, 1), mv: 12.0, diveId: 'd1'),
    (date: DateTime(2025, 6, 1), mv: 13.0, diveId: 'd2'),
  ];
  final peak = <({DateTime date, double mv, String diveId})>[
    (date: DateTime(2025, 5, 1), mv: 52.0, diveId: 'd1'),
    (date: DateTime(2025, 6, 1), mv: 48.0, diveId: 'd2'),
  ];

  testWidgets('defaults to Peak mV and toggles to Surface without error',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CellMvChart(
          surfaceSeries: surface,
          peakSeries: peak,
          baselinePeakMv: 52.0,
        ),
      ),
    ));

    expect(find.text('Peak mV'), findsOneWidget);
    expect(find.text('Surface mV'), findsOneWidget);

    await tester.tap(find.text('Surface mV'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows empty state when the active (peak) series is empty',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CellMvChart(
          surfaceSeries: surface,
          peakSeries: const [],
          baselinePeakMv: null,
        ),
      ),
    ));

    expect(find.text('No peak-mV data yet'), findsOneWidget);
  });
}
