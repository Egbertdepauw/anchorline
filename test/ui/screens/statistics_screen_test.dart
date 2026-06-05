import 'package:ccrlogger/analysis/stats/stats_result.dart';
import 'package:ccrlogger/ui/widgets/stats_bar_chart.dart';
import 'package:ccrlogger/ui/widgets/stats_mode_breakdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final years = [
    const PeriodStat(
        year: 2026, diveCount: 31, totalSeconds: 119040, maxDepthMm: 145600,
        minWaterTempC: 3.0, months: [
      PeriodStat(
          year: 2026, month: 1, diveCount: 31, totalSeconds: 119040,
          maxDepthMm: 145600, minWaterTempC: 3.0),
    ]),
    const PeriodStat(
        year: 2025, diveCount: 52, totalSeconds: 211560, maxDepthMm: 66600,
        minWaterTempC: 4.0, months: []),
  ];

  testWidgets('stats section widgets render without overflow', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 390,
          child: ListView(children: [
            StatsModeBreakdown(const [
              ModeTotal(label: 'Open circuit', representativeModeValue: 1, count: 487, totalSeconds: 1501020),
              ModeTotal(label: 'Closed circuit', representativeModeValue: 0, count: 232, totalSeconds: 901380),
            ]),
            StatsBarChart(years),
            StatsBarChart(years.first.months),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Open circuit'), findsOneWidget);
  });
}
