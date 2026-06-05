import 'package:ccrlogger/analysis/stats/stats_result.dart';
import 'package:ccrlogger/ui/widgets/stats_mode_breakdown.dart';
import 'package:ccrlogger/ui/widgets/stats_period_list.dart';
import 'package:ccrlogger/ui/widgets/stats_year_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final years = [
    const PeriodStat(
        year: 2026, diveCount: 12, totalSeconds: 36000, maxDepthMm: 53000,
        minWaterTempC: 4.0, months: [
      PeriodStat(
          year: 2026, month: 5, diveCount: 12, totalSeconds: 36000,
          maxDepthMm: 53000, minWaterTempC: 4.0),
    ]),
    const PeriodStat(
        year: 2025, diveCount: 30, totalSeconds: 90000, maxDepthMm: 71000,
        minWaterTempC: 3.6, months: []),
  ];

  testWidgets('section widgets render without overflow', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 390,
          child: ListView(children: [
            StatsModeBreakdown(const [
              ModeTotal(label: 'Closed circuit', representativeModeValue: 0, count: 38, totalSeconds: 120000),
              ModeTotal(label: 'Open circuit', representativeModeValue: 1, count: 4, totalSeconds: 9000),
            ]),
            StatsYearChart(years),
            StatsPeriodList(years, byMonth: false),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Closed circuit'), findsOneWidget);
    expect(find.text('2026'), findsWidgets);
  });
}
