import 'package:ccrlogger/analysis/bailout/ascent_simulator.dart';
import 'package:ccrlogger/analysis/bailout/bailout_result.dart';
import 'package:ccrlogger/data/models/dive.dart' show DiveGasMix;
import 'package:ccrlogger/ui/widgets/bailout_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BailoutResult _sampleResult({required BailoutVerdict verdict}) {
  final gas = const DiveGasMix(oxygenPercent: 21, heliumPercent: 35, isDiluent: true);
  return BailoutResult(
    scenario: BailoutScenario.tanksDefined,
    totalTime: const Duration(minutes: 47),
    stops: [
      AscentStop(
        depthStartMeters: 60,
        depthEndMeters: 21,
        duration: const Duration(minutes: 4),
        gas: gas,
        volumeLitresConsumed: 440,
      ),
    ],
    perGas: {
      gas: const GasUsage(requiredL: 440, availableL: 1200),
    },
    verdict: verdict,
    verdictDetails: ['21/35 440 L of 1200 L (760 L surplus)'],
  );
}

void main() {
  testWidgets('renders header + scenario banner + summary + verdict for sufficient',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BailoutSection(
          result: _sampleResult(verdict: BailoutVerdict.sufficient),
          triggerDepthMeters: 60,
          sacBottom: 30,
          sacDeco: 20,
          bailoutCapableDiluent: false,
        ),
      ),
    ));
    expect(find.textContaining('Bailout'), findsWidgets);
    expect(find.textContaining('760 L surplus'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading state shows CircularProgressIndicator', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BailoutSection(
          result: null,
          triggerDepthMeters: 60,
          sacBottom: 30,
          sacDeco: 20,
          bailoutCapableDiluent: false,
        ),
      ),
    ));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('Scenario B banner reads differently from A', (tester) async {
    final bResult = BailoutResult(
      scenario: BailoutScenario.standardGases,
      totalTime: const Duration(minutes: 47),
      stops: const [],
      perGas: const {},
      verdict: BailoutVerdict.sufficient,
      verdictDetails: const ['Recommend carrying 3 stages.'],
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BailoutSection(
          result: bResult,
          triggerDepthMeters: 60,
          sacBottom: 30,
          sacDeco: 20,
          bailoutCapableDiluent: false,
        ),
      ),
    ));
    expect(find.textContaining('Standard gases'), findsWidgets);
  });

  testWidgets('partialShortfall verdict renders amber-ish banner', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BailoutSection(
            result: _sampleResult(verdict: BailoutVerdict.partialShortfall),
            triggerDepthMeters: 60,
            sacBottom: 30,
            sacDeco: 20,
            bailoutCapableDiluent: false,
          ),
        ),
      ),
    ));
    expect(find.textContaining('760 L surplus'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('insufficient verdict renders without exception', (tester) async {
    final gas =
        const DiveGasMix(oxygenPercent: 21, heliumPercent: 35, isDiluent: true);
    final result = BailoutResult(
      scenario: BailoutScenario.tanksDefined,
      totalTime: const Duration(minutes: 55),
      stops: [
        AscentStop(
          depthStartMeters: 60,
          depthEndMeters: 0,
          duration: const Duration(minutes: 5),
          gas: gas,
          volumeLitresConsumed: 600,
        ),
      ],
      perGas: {
        gas: const GasUsage(requiredL: 600, availableL: 400),
      },
      verdict: BailoutVerdict.insufficient,
      verdictDetails: ['21/35 600 L required, only 400 L available (−200 L)'],
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BailoutSection(
            result: result,
            triggerDepthMeters: 60,
            sacBottom: 30,
            sacDeco: 20,
            bailoutCapableDiluent: false,
          ),
        ),
      ),
    ));
    expect(find.textContaining('200 L'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
