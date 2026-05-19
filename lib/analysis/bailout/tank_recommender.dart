class TankSpec {
  final String name;
  final double waterCapacityL;
  final int ratedPressureBar;
  const TankSpec({
    required this.name,
    required this.waterCapacityL,
    required this.ratedPressureBar,
  });

  /// Gas capacity at rated pressure (L).
  double get capacityL => waterCapacityL * ratedPressureBar.toDouble();
}

// Aluminium bailout stages — sized in cuft per US convention, water
// capacity in litres for the math. Rated pressure is the operational
// fill cap (the European 232 bar / 3360 psi convention; some regulators
// allow up to 3300 psi on US-spec AL tanks).
const kAl40 = TankSpec(name: 'AL40', waterCapacityL: 5.7, ratedPressureBar: 232);
const kAl50 = TankSpec(name: 'AL50', waterCapacityL: 7.0, ratedPressureBar: 232);
const kAl80 = TankSpec(name: 'AL80', waterCapacityL: 11.1, ratedPressureBar: 232);
const kTank68L300 = TankSpec(name: '6.8L/300', waterCapacityL: 6.8, ratedPressureBar: 300);
const kTank12L300 = TankSpec(name: '12L/300', waterCapacityL: 12.0, ratedPressureBar: 300);

class TankRecommendation {
  final TankSpec tank;
  final int minFillPressureBar;
  /// How many of [tank] are needed. ≥ 1. Larger than 1 when the gas
  /// volume exceeds the largest single tank's capacity — the diver
  /// has to carry multiple stages of the same gas (typical for deep
  /// dives on a helium-rich bottom mix).
  final int count;
  const TankRecommendation({
    required this.tank,
    required this.minFillPressureBar,
    this.count = 1,
  });
}

/// Pick the smallest single tank in [availableTanks] that can hold
/// [volumeLitres] at-or-below its rated pressure. If no single tank
/// fits, fall back to MULTIPLE of the largest tank, sized so each
/// holds roughly the same fraction of the total volume at a
/// rated-or-lower fill pressure.
///
/// Returns null only when [availableTanks] itself is empty.
///
/// [availableTanks] should be sorted smallest-to-largest by water
/// capacity.
TankRecommendation? recommend({
  required double volumeLitres,
  required List<TankSpec> availableTanks,
}) {
  if (availableTanks.isEmpty) return null;
  // Single-tank pass — smallest tank that fits.
  for (final tank in availableTanks) {
    final minFill = (volumeLitres / tank.waterCapacityL).ceil();
    if (minFill <= tank.ratedPressureBar) {
      return TankRecommendation(
        tank: tank,
        minFillPressureBar: minFill,
        count: 1,
      );
    }
  }
  // Multi-tank fallback: use the largest tank. count = ceil(total / one
  // tank's capacity at rated pressure). Each carries volume / count
  // litres, which fits below the rated pressure by construction.
  final largest = availableTanks.last;
  final perTankCapacityL =
      largest.waterCapacityL * largest.ratedPressureBar.toDouble();
  final count = (volumeLitres / perTankCapacityL).ceil();
  final minFillPerTank =
      (volumeLitres / count / largest.waterCapacityL).ceil();
  return TankRecommendation(
    tank: largest,
    minFillPressureBar: minFillPerTank,
    count: count,
  );
}
