import 'package:ccrlogger/analysis/bailout/tank_recommender.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('500 L → AL40 (88 bar)', () {
    final r = recommend(
      volumeLitres: 500,
      availableTanks: [kAl40, kAl80],
    );
    expect(r, isNotNull);
    expect(r!.tank.name, 'AL40');
    expect(r.minFillPressureBar, closeTo(88, 1));
  });

  test('1465 L → AL80 (132 bar)', () {
    final r = recommend(
      volumeLitres: 1465,
      availableTanks: [kAl40, kAl80],
    );
    expect(r, isNotNull);
    expect(r!.tank.name, 'AL80');
    expect(r.minFillPressureBar, closeTo(132, 1));
  });

  test('4000 L without 12L/300 → null (nothing fits)', () {
    final r = recommend(
      volumeLitres: 4000,
      availableTanks: [kAl40, kAl80, kTank68L300],
    );
    expect(r, isNull);
  });

  test('4000 L with 12L/300 → 12L/300 (~334 bar?? no — clamps to a valid fill)', () {
    // 4000 / 12 = 333 bar, > rated 300 — null
    final r = recommend(
      volumeLitres: 4000,
      availableTanks: [kAl40, kAl80, kTank68L300, kTank12L300],
    );
    expect(r, isNull);
  });

  test('3500 L → 12L/300 (~292 bar)', () {
    final r = recommend(
      volumeLitres: 3500,
      availableTanks: [kAl40, kAl80, kTank68L300, kTank12L300],
    );
    expect(r, isNotNull);
    expect(r!.tank.name, '12L/300');
  });

  test('empty available list → null', () {
    final r = recommend(volumeLitres: 100, availableTanks: []);
    expect(r, isNull);
  });
}
