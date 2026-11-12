import 'package:ccrlogger/analysis/bailout/ascent_simulator.dart';
import 'package:ccrlogger/analysis/bailout/bailout_result.dart';
import 'package:ccrlogger/analysis/planner/plan_result.dart';
import 'package:subsurface_core/data/models/dive.dart';
import 'package:ccrlogger/data/models/dive_plan.dart' show DivePlanMode;
import 'package:ccrlogger/ui/widgets/plan_output_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows summary chips when result is non-null', (tester) async {
    const air = DiveGasMix(
        oxygenPercent: 21, heliumPercent: 0, isDiluent: true);
    final result = PlanResult(
      profile: const [],
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
      oxygenConsumedLitres: 30,
      gasConsumedLitres: 30,
      gasConsumedByMix: const [],
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

  testWidgets(
      'OC mode renders per-gas consumption chips (one per mix) instead '
      'of a single lumped Gas chip', (tester) async {
    const tx = DiveGasMix(
        oxygenPercent: 18, heliumPercent: 45, isDiluent: true);
    const ean50 = DiveGasMix(
        oxygenPercent: 50, heliumPercent: 0, isDiluent: false);
    final result = PlanResult(
      profile: const [],
      diveAscent: const [],
      bailout: BailoutResult(
        scenario: BailoutScenario.tanksDefined,
        totalTime: const Duration(minutes: 5),
        stops: const [],
        perGas: const {},
        verdict: BailoutVerdict.sufficient,
        verdictDetails: const [],
      ),
      cnsPercent: 12.5,
      otuTotal: 80,
      maxDensityGramsPerLitre: 4.2,
      totalRuntime: const Duration(minutes: 30),
      oxygenConsumedLitres: 30,
      gasConsumedLitres: 4380,
      gasConsumedByMix: [
        (gas: tx, litres: 3400),
        (gas: ean50, litres: 980),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanOutputSection(
          result: result,
          scheme: ThemeData.dark().colorScheme,
          mode: DivePlanMode.oc,
        ),
      ),
    ));
    expect(find.text('Tx18/45 3400 L'), findsOneWidget);
    expect(find.text('EAN50 980 L'), findsOneWidget);
    // The lumped fallback is NOT shown when a per-gas list is present.
    expect(find.text('Gas 4380 L'), findsNothing);
  });
}
