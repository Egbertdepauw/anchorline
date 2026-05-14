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
  const TankRecommendation({required this.tank, required this.minFillPressureBar});
}

/// Picks the smallest tank in [availableTanks] that can hold [volumeLitres]
/// at-or-below its rated pressure. Returns null if no tank fits.
/// availableTanks should be sorted smallest-to-largest by water capacity.
TankRecommendation? recommend({
  required double volumeLitres,
  required List<TankSpec> availableTanks,
}) {
  for (final tank in availableTanks) {
    final minFill = (volumeLitres / tank.waterCapacityL).ceil();
    if (minFill <= tank.ratedPressureBar) {
      return TankRecommendation(tank: tank, minFillPressureBar: minFill);
    }
  }
  return null;
}
