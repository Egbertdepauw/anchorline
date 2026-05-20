/// Real-gas behaviour for blending math.
///
/// Implementation is van der Waals:
///   (P + a/v²)(v − b) = RT
/// where v is the molar volume, a accounts for inter-molecular
/// attraction, and b for the finite size of molecules. vdW matches the
/// reference blender-toolkit's "Real gas (vdW)" mode to within a
/// fraction of a bar at tech-diving pressures (up to ~300 bar) — much
/// closer than the previous piecewise-linear Z-lookup, which
/// underestimated helium's Z curvature and produced sum-over-target
/// fill plans.
///
/// Mixtures use simple mole-weighted mixing rules:
///   a_mix = (Σ x_i · √a_i)²   (Berthelot / geometric)
///   b_mix = Σ x_i · b_i       (Linear / Amagat)
///
/// All temperatures internal here are Kelvin; pressures bar; volumes
/// litres; amounts moles. R is in L·bar/(mol·K).
library;

import 'dart:math' as math;

const double _kR = 0.08314; // L·bar/(mol·K)

/// Default blending temperature: 18 °C — matches the reference
/// blender-toolkit's default and is the typical blending-station
/// temperature. The cold-water 15 °C convention is too low to model
/// the gas mass that actually fits in a cylinder filled indoors.
const double kDefaultBlendingTempKelvin = 291.15;

// vdW constants — a in L²·bar/mol², b in L/mol. CRC Handbook values.
const double _aHe = 0.0346;
const double _bHe = 0.0237;
const double _aO2 = 1.382;
const double _bO2 = 0.0319;
const double _aN2 = 1.370;
const double _bN2 = 0.0387;

/// Mole-fraction-weighted compressibility factor for a mix at
/// [pressureBar] and [temperatureKelvin]. Returns 1.0 for the zero-
/// pressure case so the rest of the math degenerates gracefully when a
/// cylinder is empty.
double compressibilityFor({
  required double fO2,
  required double fHe,
  required double pressureBar,
  double temperatureKelvin = kDefaultBlendingTempKelvin,
}) {
  if (pressureBar <= 0) return 1.0;
  final fN2 = 1.0 - fO2 - fHe;
  final aMix = _aMix(fO2: fO2, fHe: fHe, fN2: fN2);
  final bMix = _bMix(fO2: fO2, fHe: fHe, fN2: fN2);
  final v = _solveMolarVolume(pBar: pressureBar, t: temperatureKelvin, a: aMix, b: bMix);
  return pressureBar * v / (_kR * temperatureKelvin);
}

/// Total moles in a cylinder of [volumeL] at [pressureBar] gauge with
/// mole fractions ([fO2], [fHe]) at [temperatureKelvin]. Real-gas via
/// vdW; degenerate to ideal-gas when [useRealGas] is false.
double molesForGauge({
  required double pressureBar,
  required double volumeL,
  required double fO2,
  required double fHe,
  double temperatureKelvin = kDefaultBlendingTempKelvin,
  bool useRealGas = true,
}) {
  if (pressureBar <= 0) return 0;
  final rt = _kR * temperatureKelvin;
  if (!useRealGas) {
    return pressureBar * volumeL / rt;
  }
  final fN2 = 1.0 - fO2 - fHe;
  final aMix = _aMix(fO2: fO2, fHe: fHe, fN2: fN2);
  final bMix = _bMix(fO2: fO2, fHe: fHe, fN2: fN2);
  final v = _solveMolarVolume(pBar: pressureBar, t: temperatureKelvin, a: aMix, b: bMix);
  return volumeL / v;
}

/// Inverse of [molesForGauge]: total moles + composition + cylinder
/// volume + temperature → gauge pressure (bar). Used to advance the
/// fill plan sequentially in mole space (compute the gauge pressure
/// after each fill step rather than scaling per-leg by Z).
double gaugeForMoles({
  required double nMol,
  required double volumeL,
  required double fO2,
  required double fHe,
  double temperatureKelvin = kDefaultBlendingTempKelvin,
  bool useRealGas = true,
}) {
  if (nMol <= 0 || volumeL <= 0) return 0;
  final rt = _kR * temperatureKelvin;
  if (!useRealGas) {
    return nMol * rt / volumeL;
  }
  final fN2 = 1.0 - fO2 - fHe;
  final aMix = _aMix(fO2: fO2, fHe: fHe, fN2: fN2);
  final bMix = _bMix(fO2: fO2, fHe: fHe, fN2: fN2);
  final v = volumeL / nMol;
  // Direct vdW solve — no iteration needed: given v, T, a, b, solve P.
  if (v <= bMix) {
    // Co-volume crisis: more moles than the b-volume allows. Shouldn't
    // happen for realistic blends; return a sentinel finite-but-huge
    // pressure rather than blowing up.
    return 1e6;
  }
  return rt / (v - bMix) - aMix / (v * v);
}

double _aMix({required double fO2, required double fHe, required double fN2}) {
  final sqrtA = fHe * math.sqrt(_aHe) +
      fO2 * math.sqrt(_aO2) +
      fN2 * math.sqrt(_aN2);
  return sqrtA * sqrtA;
}

double _bMix({required double fO2, required double fHe, required double fN2}) =>
    fHe * _bHe + fO2 * _bO2 + fN2 * _bN2;

/// Newton iteration on v: P = RT/(v − b) − a/v². Convergence is
/// quadratic for the physical (gas) branch of the cubic.
double _solveMolarVolume({
  required double pBar,
  required double t,
  required double a,
  required double b,
}) {
  final rt = _kR * t;
  // Seed at ideal-gas molar volume; vdW gas branch sits very close.
  var v = rt / pBar;
  for (var i = 0; i < 50; i++) {
    final num = (v - b);
    if (num <= 0) {
      // Pushed past the co-volume — back off rather than diverge.
      v = b * 1.001;
      continue;
    }
    final f = rt / num - a / (v * v) - pBar;
    final fPrime = -rt / (num * num) + 2 * a / (v * v * v);
    if (fPrime.abs() < 1e-18) break;
    final dv = -f / fPrime;
    v += dv;
    if (dv.abs() < 1e-12) break;
  }
  return v;
}
