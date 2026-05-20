import 'package:ccrlogger/analysis/bailout/ascent_simulator.dart';
import 'package:ccrlogger/analysis/bailout/bailout_result.dart';
import 'package:ccrlogger/analysis/planner/plan_result.dart';
import 'package:ccrlogger/data/models/dive.dart';
import 'package:ccrlogger/ui/widgets/plan_output_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows summary chips when result is non-null', (tester) async {
    const air = DiveGasMix(
        oxygenPercent: 21, heliumPercent: 0, isDiluent: true);
    final result = PlanResult(
      diveAscent: const [],
      bailout: BailoutResult(
        scenario: BailoutScenario.tanksDefined,
        totalTime: const Duration(minutes: 5),
        stops: const [
          AscentStop(
              depthStartMeters: 0,
              depthEndMeters: 0,
              duration: Duration(minutes: 5),
              gas: air,
              volumeLitresConsumed: 100),
        ],
        perGas: {},
        verdict: BailoutVerdict.sufficient,
        verdictDetails: const [],
      ),
      cnsPercent: 12.5,
      otuTotal: 80,
      maxDensityGramsPerLitre: 4.2,
      totalRuntime: const Duration(minutes: 30),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanOutputSection(result: result, scheme: ThemeData.dark().colorScheme),
      ),
    ));
    expect(find.textContaining('CNS'), findsOneWidget);
    expect(find.textContaining('12.5'), findsOneWidget);
    expect(find.textContaining('OTU'), findsOneWidget);
  });

  testWidgets('shows hint when result is null (empty plan)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanOutputSection(result: null, scheme: ThemeData.dark().colorScheme),
      ),
    ));
    expect(find.textContaining('Add gases and segments'), findsOneWidget);
  });
}
