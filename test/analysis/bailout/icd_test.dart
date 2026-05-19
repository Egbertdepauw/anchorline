import 'package:ccrlogger/analysis/bailout/ascent_simulator.dart';
import 'package:ccrlogger/analysis/bailout/icd.dart';
import 'package:ccrlogger/data/models/dive.dart' show DiveGasMix;
import 'package:flutter_test/flutter_test.dart';

const _tx1070 = DiveGasMix(oxygenPercent: 10, heliumPercent: 70, isDiluent: true);
const _tx2135 =
    DiveGasMix(oxygenPercent: 21, heliumPercent: 35, isDiluent: false);
const _tx3525 =
    DiveGasMix(oxygenPercent: 35, heliumPercent: 25, isDiluent: false);
const _ean50 =
    DiveGasMix(oxygenPercent: 50, heliumPercent: 0, isDiluent: false);
const _o2 = DiveGasMix(oxygenPercent: 100, heliumPercent: 0, isDiluent: false);

AscentStop _stop(DiveGasMix gas, double depth) => AscentStop(
      depthStartMeters: depth,
      depthEndMeters: depth,
      duration: const Duration(minutes: 1),
      gas: gas,
      volumeLitresConsumed: 0,
    );

void main() {
  test('no switches → no risks', () {
    expect(detectIcdRisks([_stop(_tx2135, 30)]), isEmpty);
  });

  test('21/35 → 35/25: 5:1 broken but small absolute He drop = marginal', () {
    // ΔO₂=+14, ΔHe=-10. ratio=1.4 → over the rule, but |ΔHe|=10 < 20
    // so we class this as marginal, not severe.
    final risks = detectIcdRisks([_stop(_tx2135, 36), _stop(_tx3525, 36)]);
    expect(risks.length, 1);
    expect(risks.single.severity, IcdSeverity.marginal);
  });

  test('10/70 → EAN50 (skip intermediates): severe — big He drop, rule broken',
      () {
    // ΔO₂=+40, ΔHe=-70. ratio=0.57, |ΔHe|=70 ≥ 20 → severe.
    final risks = detectIcdRisks([_stop(_tx1070, 21), _stop(_ean50, 21)]);
    expect(risks.length, 1);
    expect(risks.single.severity, IcdSeverity.severe);
    expect(risks.single.deltaO2, 40);
    expect(risks.single.deltaHe, -70);
  });

  test('21/35 → EAN50: severe (|ΔHe|=35 ≥ 20)', () {
    final risks = detectIcdRisks([_stop(_tx2135, 21), _stop(_ean50, 21)]);
    expect(risks.single.severity, IcdSeverity.severe);
  });

  test('EAN50 → O₂: no He movement → no ICD risk', () {
    final risks = detectIcdRisks([_stop(_ean50, 6), _stop(_o2, 6)]);
    expect(risks, isEmpty);
  });

  test('multi-stage ascent with intermediates flags only the He-dump switches',
      () {
    // 10/70 → 21/35 → 35/25 → EAN50 → O2
    final risks = detectIcdRisks([
      _stop(_tx1070, 57),
      _stop(_tx2135, 57),
      _stop(_tx3525, 36),
      _stop(_ean50, 21),
      _stop(_o2, 6),
    ]);
    // 3 helium-bearing switches; EAN50→O₂ has no He movement so is skipped.
    expect(risks.length, 3);
    // 10/70 → 21/35: ΔHe=-35 ≥ 20 → severe
    expect(risks[0].severity, IcdSeverity.severe);
    // 21/35 → 35/25: ΔHe=-10 < 20 → marginal
    expect(risks[1].severity, IcdSeverity.marginal);
    // 35/25 → EAN50: ΔHe=-25 ≥ 20 → severe
    expect(risks[2].severity, IcdSeverity.severe);
  });
}
