/// Per-sample gas-density computation for the active gas mix at each
/// depth. Used as a chart trace (colour-banded by safety thresholds)
/// and a max-value StatTile on the dive detail screen.
library;

import 'dart:typed_data';

import '../data/models/dive.dart' show DiveGasMix;

/// Standard atmospheric pressure constant (mbar) used as a fallback.
const int kStandardAtmosphericPressureMbar = 1013;

/// Density of each pure gas at 1 ATA (g/L), per the Anthony/Mitchell
/// CCR-density safety paper.
const double kO2DensityAt1Atm = 1.314;
/// N₂ value derived from ISA standard air density (1.225 g/L at 15 °C,
/// 1013.25 mbar) with the inert fraction treated as pure N₂:
/// (1.225 − 0.21 × 1.314) / 0.79 ≈ 1.2013 g/L. This "effective N₂"
/// absorbs the small Ar contribution (≈1% of air) and aligns the weighted
/// sum for air exactly with the standard atmosphere value.
const double kN2DensityAt1Atm = 1.2013;
const double kHeDensityAt1Atm = 0.166;

/// Density colour-band thresholds (g/L). Per Track B brainstorm —
/// standard tech (matches Shearwater's own warning at 5.7).
const double kDensityOrangeThreshold = 5.2;
const double kDensityRedThreshold = 5.7;

enum DensityBand { green, orange, red }

DensityBand densityBand(double densityGramsPerLitre) {
  if (densityGramsPerLitre >= kDensityRedThreshold) return DensityBand.red;
  if (densityGramsPerLitre >= kDensityOrangeThreshold) return DensityBand.orange;
  return DensityBand.green;
}

/// Weighted gas density at 1 ATA. [o2Fraction] and [heFraction] are
/// 0.0–1.0 (not percentages). N₂ is inferred as the remainder.
double mixDensityAt1Atm(double o2Fraction, double heFraction) {
  final n2Fraction = 1.0 - o2Fraction - heFraction;
  return o2Fraction * kO2DensityAt1Atm +
      heFraction * kHeDensityAt1Atm +
      n2Fraction * kN2DensityAt1Atm;
}

/// Per-sample gas density (g/L) at ambient pressure. Walks
/// [depthMeters] and [gasMixIndex] in parallel; multiplies the mix's
/// 1 ATA density by ambient pressure (atm + depth/10).
Float32List computeDensitySeries({
  required Float32List depthMeters,
  required Uint8List gasMixIndex,
  required List<DiveGasMix> gasMixes,
  required int atmosphericPressureMbar,
}) {
  assert(depthMeters.length == gasMixIndex.length);
  final out = Float32List(depthMeters.length);
  // Pre-compute density at 1 ATA per mix — avoid recomputing in the loop.
  final densityByMix = Float32List(gasMixes.length);
  for (var i = 0; i < gasMixes.length; i++) {
    densityByMix[i] = mixDensityAt1Atm(
      gasMixes[i].oxygenPercent / 100.0,
      gasMixes[i].heliumPercent / 100.0,
    );
  }
  final atmBar = atmosphericPressureMbar / 1000.0;
  for (var i = 0; i < depthMeters.length; i++) {
    final mixIdx = gasMixIndex[i];
    if (mixIdx >= densityByMix.length) {
      out[i] = double.nan;
      continue;
    }
    final ambientBar = atmBar + depthMeters[i] / 10.0;
    out[i] = densityByMix[mixIdx] * ambientBar;
  }
  return out;
}
