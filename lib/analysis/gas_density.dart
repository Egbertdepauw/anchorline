/// Per-sample gas-density computation for the active gas mix at each
/// depth. Used as a chart trace (colour-banded by safety thresholds)
/// and a max-value StatTile on the dive detail screen.
library;

import 'dart:typed_data';

import 'package:subsurface_core/data/models/dive.dart' show DiveGasMix;
import 'loop_gas.dart';

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

/// Per-sample gas density (g/L) at ambient pressure.
///
/// For OC samples (no setpoint, or no diluent in [gasMixes]) the density
/// is computed from the static gas mix at the sample's [gasMixIndex] —
/// the original behaviour.
///
/// For CCR samples (signalled by a positive [ppo2Bar] and the presence
/// of a diluent in [gasMixes]) the density uses the LIVE LOOP GAS at
/// that sample, computed by [loopGasAt] from the diluent's inert
/// composition + the per-sample PPO₂. This matches what the dive
/// computer displays as "current gas" and produces the correct value
/// at depth — previously CCR samples would silently use whichever
/// static mix the parser happened to assign (often the OC bailout),
/// which gave density values almost a factor of 2 too high.
///
/// [ppo2Bar] should be the per-sample VOTED / measured PPO₂ (not the
/// setpoint target) so transient cell drift / solenoid lag / dil
/// flushes show up correctly in the density trace. Pass null for OC
/// dives, or for CCR dives where the per-sample voted PPO₂ isn't
/// available (fall back to the setpoint trace if you must).
Float32List computeDensitySeries({
  required Float32List depthMeters,
  required Uint8List gasMixIndex,
  required List<DiveGasMix> gasMixes,
  required int atmosphericPressureMbar,
  Float32List? ppo2Bar,
}) {
  assert(depthMeters.length == gasMixIndex.length);
  assert(ppo2Bar == null || ppo2Bar.length == depthMeters.length);
  final out = Float32List(depthMeters.length);
  // Pre-compute density at 1 ATA per static mix — avoid recomputing in
  // the loop. CCR loop-gas density is computed per sample below.
  final densityByMix = Float32List(gasMixes.length);
  for (var i = 0; i < gasMixes.length; i++) {
    densityByMix[i] = mixDensityAt1Atm(
      gasMixes[i].oxygenPercent / 100.0,
      gasMixes[i].heliumPercent / 100.0,
    );
  }
  final atmBar = atmosphericPressureMbar / 1000.0;
  // Pre-resolve a fallback diluent — the one with the LOWEST O₂
  // fraction (= most He = depth-tolerant). Used only when the sample's
  // own gasMixIndex doesn't point at a diluent. This handles two
  // cases at once:
  //
  // (a) Multi-diluent dives where Subsurface recorded a gas change to a
  //     non-diluent cylinder (deco / bailout) at depth. The diver wasn't
  //     actually breathing that gas on a CCR loop — they stayed on the
  //     deepest diluent. Falling back to that diluent reflects reality.
  //
  // (b) Single-diluent dives where the parser mis-indexed the sample
  //     (dive-702 bug). Falling back to the diluent gives the correct
  //     loop-gas answer.
  //
  // Multi-diluent dives where the sample's gasMixIndex DOES point at a
  // diluent (e.g. a mid-dive switch to a shallower-rated diluent) still
  // use that diluent per the active-diluent path below.
  final fallbackDil = deepestDiluent(gasMixes);
  for (var i = 0; i < depthMeters.length; i++) {
    final ambientBar = atmBar + depthMeters[i] / 10.0;
    final live = ppo2Bar?[i] ?? 0.0;
    final mixIdx = gasMixIndex[i];
    if (mixIdx >= densityByMix.length) {
      out[i] = double.nan;
      continue;
    }
    if (live > 0) {
      // CCR loop-gas mode. Prefer the gas the sample is currently on if
      // it IS a diluent (handles multi-diluent dives), else fall back
      // to the first diluent in the list.
      final atIdx = gasMixes[mixIdx];
      final activeDil =
          atIdx.isDiluent ? atIdx : fallbackDil;
      if (activeDil != null) {
        final loop = loopGasAt(
          depthMeters: depthMeters[i],
          ppo2Bar: live,
          diluent: activeDil,
          atmosphericPressureBar: atmBar,
        );
        out[i] =
            mixDensityAt1Atm(loop.o2Fraction, loop.heFraction) * ambientBar;
        continue;
      }
    }
    out[i] = densityByMix[mixIdx] * ambientBar;
  }
  return out;
}
