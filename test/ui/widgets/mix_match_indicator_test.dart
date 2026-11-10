import 'package:ccrlogger/analysis/mix_match.dart';
import 'package:ccrlogger/data/models/gas_analysis.dart';
import 'package:ccrlogger/ui/theme/safety_colors.dart';
import 'package:ccrlogger/ui/widgets/mix_match_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  required double o2,
  required double he,
  required DesiredMix desired,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MixMatchIndicator(
          o2Percent: o2,
          hePercent: he,
          desired: desired,
        ),
      ),
    ),
  );
}

Color? _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  test('mixMatchColor maps each level to a safety colour', () {
    expect(mixMatchColor(MixMatchLevel.match), SafetyColors.success);
    expect(mixMatchColor(MixMatchLevel.orange), SafetyColors.warning);
    expect(mixMatchColor(MixMatchLevel.red), SafetyColors.danger);
    expect(mixMatchColor(MixMatchLevel.hard), SafetyColors.danger);
  });

  group('MixMatchIndicator', () {
    testWidgets('match: green numbers and "Matches …"', (tester) async {
      await _pump(
        tester,
        o2: 20.6,
        he: 33.8,
        desired: const DesiredMix(21, 35),
      );

      expect(find.byKey(const ValueKey('mix-match-indicator')), findsOneWidget);
      expect(find.text('O2 20.6  He 33.8'), findsOneWidget);
      expect(find.text('Matches Tx21/35'), findsOneWidget);
      expect(_colorOf(tester, 'O2 20.6  He 33.8'), SafetyColors.success);
      expect(_colorOf(tester, 'Matches Tx21/35'), SafetyColors.success);
    });

    testWidgets('orange: orange numbers and the "off" line', (tester) async {
      await _pump(
        tester,
        o2: 33.5,
        he: 0,
        desired: const DesiredMix(32, 0),
      );

      expect(find.text('O2 33.5  He 0.0'), findsOneWidget);
      expect(find.text('O2 1.5 off EAN32'), findsOneWidget);
      expect(_colorOf(tester, 'O2 33.5  He 0.0'), SafetyColors.warning);
      expect(_colorOf(tester, 'O2 1.5 off EAN32'), SafetyColors.warning);
    });

    testWidgets('orange from helium alone', (tester) async {
      await _pump(
        tester,
        o2: 21,
        he: 38.5,
        desired: const DesiredMix(21, 35),
      );

      expect(find.text('He 3.5 off Tx21/35'), findsOneWidget);
      expect(_colorOf(tester, 'O2 21.0  He 38.5'), SafetyColors.warning);
    });

    testWidgets('red: red numbers and the "off" line', (tester) async {
      await _pump(
        tester,
        o2: 36,
        he: 0,
        desired: const DesiredMix(32, 0),
      );

      expect(find.text('O2 4.0 off EAN32'), findsOneWidget);
      expect(_colorOf(tester, 'O2 36.0  He 0.0'), SafetyColors.danger);
      expect(_colorOf(tester, 'O2 4.0 off EAN32'), SafetyColors.danger);
    });

    testWidgets('hard mismatch: red numbers and the "off" line',
        (tester) async {
      await _pump(
        tester,
        o2: 32.1,
        he: 0,
        desired: const DesiredMix(50, 0),
      );

      expect(find.text('O2 17.9 off EAN50'), findsOneWidget);
      expect(_colorOf(tester, 'O2 32.1  He 0.0'), SafetyColors.danger);
      expect(_colorOf(tester, 'O2 17.9 off EAN50'), SafetyColors.danger);
    });

    testWidgets('updates as the reading changes', (tester) async {
      await _pump(tester, o2: 50, he: 0, desired: const DesiredMix(50, 0));
      expect(find.text('Matches EAN50'), findsOneWidget);

      await _pump(tester, o2: 45, he: 0, desired: const DesiredMix(50, 0));
      expect(find.text('Matches EAN50'), findsNothing);
      expect(find.text('O2 5.0 off EAN50'), findsOneWidget);
      expect(_colorOf(tester, 'O2 45.0  He 0.0'), SafetyColors.danger);
    });
  });
}
