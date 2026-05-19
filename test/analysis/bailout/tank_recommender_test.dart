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

  test('4000 L without 12L/300 → multi-tank recommendation', () {
    // No single tank in the list can hold 4000 L. Fall back to 2 of the
    // largest (AL80 = 11.1 L × 232 bar = 2575 L). 4000 L / 2 = 2000 L per
    // tank → 2000/11.1 = ceil(180.18) = 181 bar per tank.
    final r = recommend(
      volumeLitres: 4000,
      availableTanks: [kAl40, kAl80, kTank68L300],
    );
    expect(r, isNotNull);
    expect(r!.count, 2);
    expect(r.tank.name, '6.8L/300');
    expect(r.minFillPressureBar, lessThanOrEqualTo(r.tank.ratedPressureBar));
  });

  test('4000 L with 12L/300 → 2× 12L/300 multi-tank', () {
    // 4000 L > 1× 12L/300 capacity (3600 L). Fall back to 2× 12L/300,
    // each filled to ceil(4000/2/12) = 167 bar.
    final r = recommend(
      volumeLitres: 4000,
      availableTanks: [kAl40, kAl80, kTank68L300, kTank12L300],
    );
    expect(r, isNotNull);
    expect(r!.count, 2);
    expect(r.tank.name, '12L/300');
    expect(r.minFillPressureBar, 167);
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
