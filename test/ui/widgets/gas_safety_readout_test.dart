import 'package:ccrlogger/data/models/dive_plan.dart';
import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:ccrlogger/ui/widgets/gas_safety_readout.dart';
import 'package:ccrlogger/ui/widgets/plan_gases_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _statusSuccess = Color(0xFF4ADE80);
const _statusWarning = Color(0xFFF39C12);
const _statusDanger = Color(0xFFE74C3C);
const _idle = Color(0xFFA0AEB6);

void main() {
  group('computeGasSafetyReadout', () {
    test('green when OC PPO2 ≤ 1.1 AND END ≤ 30 m, even on a hypoxic mix',
        () {
      // Tx 15/55 at 60 m: PPO₂ = 0.15 × 7.013 ≈ 1.05 (under 1.1),
      // END = (60+10) × 0.45 - 10 = 21.5 m (under 30) → GREEN even
      // though fO₂ is hypoxic.
      const gas = DivePlanGas(
          oxygenPercent: 15, heliumPercent: 55, isDiluent: true);
      final r = computeGasSafetyReadout(gas, 60, idleColor: _idle);
      expect(r, isNotNull);
      expect(r!.color, equals(_statusSuccess));
      expect(r.isUnsafe, isFalse);
      expect(r.isWarning, isFalse);
    });

    test('orange when 1.1 < PPO2 ≤ 1.51 at the evaluated depth', () {
      // EAN 32 at 30 m: PPO₂ = 0.32 × 4.013 ≈ 1.28 → AMBER.
      const gas = DivePlanGas(
          oxygenPercent: 32, heliumPercent: 0, isDiluent: true);
      final r = computeGasSafetyReadout(gas, 30, idleColor: _idle);
      expect(r!.color, equals(_statusWarning));
      expect(r.isWarning, isTrue);
      expect(r.isUnsafe, isFalse);
    });

    test('red when PPO2 > 1.51 at the evaluated depth', () {
      // EAN 32 at 50 m: PPO₂ ≈ 1.92 → RED, unsafe flag set.
      const gas = DivePlanGas(
          oxygenPercent: 32, heliumPercent: 0, isDiluent: true);
      final r = computeGasSafetyReadout(gas, 50, idleColor: _idle);
      expect(r!.color, equals(_statusDanger));
      expect(r.isUnsafe, isTrue);
    });

    test('END > 30 m forces amber even when PPO2 is under 1.1', () {
      // Tx 21/35 at 60 m: PPO₂ = 0.21 × 7.013 ≈ 1.47 → already amber
      // on PPO2, but the END check applies too — END = 70 × 0.65 - 10
      // = 35.5 m. We want a case where ONLY END is the trigger:
      // Tx 21/20 at 30 m: PPO₂ ≈ 0.84 (under 1.1), END = 40 × 0.80 - 10
      // = 22 m → green. Use a deeper depth: 50 m → PPO₂ ≈ 1.26 amber.
      // So crafting a "END-only amber" case at depth where PPO2 stays
      // under 1.1 requires fO2 low AND fHe low — impractical. We check
      // the broader case: 21/0 (Air) at 40 m: PPO₂ ≈ 1.05, END = 50 m
      // (40+10) since fHe=0. That's an END-only amber, since narcosis
      // logic treats no-He mix's END = depth.
      const gas = DivePlanGas(
          oxygenPercent: 21, heliumPercent: 0, isDiluent: true);
      final r = computeGasSafetyReadout(gas, 40, idleColor: _idle);
      expect(r!.isWarning, isTrue);
      expect(r.color, equals(_statusWarning));
    });
  });

  group('isGasSelectableAt (PPO2 hard-cap 1.61)', () {
    test('EAN 50 is selectable at 21 m but NOT at 24 m', () {
      const ean50 = DivePlanGas(
          oxygenPercent: 50, heliumPercent: 0, isDiluent: false);
      // PPO2 at 21 m = 0.50 × 3.113 ≈ 1.56 → selectable.
      expect(isGasSelectableAt(ean50, 21), isTrue);
      // PPO2 at 24 m = 0.50 × 3.413 ≈ 1.71 → NOT selectable.
      expect(isGasSelectableAt(ean50, 24), isFalse);
    });

    test('Trimix 18/45 stays selectable at 60 m', () {
      const tx18_45 = DivePlanGas(
          oxygenPercent: 18, heliumPercent: 45, isDiluent: true);
      // PPO2 at 60 m = 0.18 × 7.013 ≈ 1.26 → selectable.
      expect(isGasSelectableAt(tx18_45, 60), isTrue);
    });
  });

  testWidgets('idle readout text follows the theme textSecondary',
      (tester) async {
    final theme = AppThemes.byId('miasma');
    await tester.pumpWidget(MaterialApp(
      theme: theme.themeData,
      home: Scaffold(
        body: PlanGasesEditor(
          gases: const [
            DivePlanGas(oxygenPercent: 10, heliumPercent: 80, isDiluent: true),
          ],
          onAdd: (_) {},
          onRemove: (_) {},
          onReplace: (_, _) {},
        ),
      ),
    ));
    // No segments use the gas and END at its MOD is under 30 m, so the
    // readout is idle (neither warning nor safe).
    final text = tester.widget<Text>(find.textContaining('MOD '));
    expect(text.style!.color, theme.palette.textSecondary);
  });
}
