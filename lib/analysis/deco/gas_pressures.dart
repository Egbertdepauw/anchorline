/// Inert-gas partial-pressure helpers shared by the deco replay engines.
///
/// On open circuit, PN2/PHe are the gas-fraction shares of the inhaled
/// pressure. On a closed circuit with the loop controller holding O2 at
/// `setpointBar`, the inert pressures are the share of (ambient − setpoint
/// − water vapour) divided among the diluent's helium and nitrogen in
/// their natural ratio — the loop is the diluent's inerts on top of pure
/// O2 injected to maintain the setpoint.
library;

import 'dart:math';

import 'package:subsurface_core/data/models/dive.dart' show DiveGasMix;

const double waterVapourPressureBar = 0.0627;

/// N2 partial pressure in the lungs at surface equilibrium on air, at the
/// canonical 1.013-bar sea-level surface pressure. Kept as a default for
/// engines + tests that don't carry the dive's actual atmospheric pressure;
/// production replays should call [surfaceEquilibriumN2BarAt] with the
/// value the dive computer recorded.
const double surfaceEquilibriumN2Bar = (1.013 - waterVapourPressureBar) * 0.79;

/// Pre-dive tissue N2 saturation at an arbitrary surface pressure.
/// Use this when replaying a dive logged at altitude or on a day whose
/// barometric pressure deviates from 1.013 — the Petrel records this on
/// every dive and using it instead of the constant tightens the resulting
/// SurfGF / GF99 values against what Subsurface computes.
double surfaceEquilibriumN2BarAt(double surfacePressureBar) =>
    (surfacePressureBar - waterVapourPressureBar) * 0.79;

/// Returns (paN2, paHe) — the inert-gas partial pressures the diver is
/// actually inhaling at this sample.
///
/// When `setpointBar` ≤ 0.1, the diver is on open circuit; PN2/PHe scale
/// with the gas's own fractions. When `setpointBar` > 0.1, treat the dive
/// as CCR: the loop is `setpointBar` of O2 plus the diluent's inerts
/// scaled to fill the remaining headroom. If the setpoint exceeds what
/// the depth can support (e.g. shallow stops on 1.3 bar), the inerts go
/// to zero — the loop is effectively pure O2.
(double, double) inertPartialPressures({
  required double ambientBar,
  required DiveGasMix mix,
  required double setpointBar,
}) {
  final fO2 = mix.oxygenPercent / 100.0;
  final fHe = mix.heliumPercent / 100.0;
  final fN2 = 1.0 - fO2 - fHe;
  final inhaledPressure = ambientBar - waterVapourPressureBar;

  if (setpointBar <= 0.1) {
    return (inhaledPressure * fN2, inhaledPressure * fHe);
  }

  final inertHeadroom = max(0.0, inhaledPressure - setpointBar);
  final fInertTotal = fN2 + fHe;
  if (fInertTotal <= 0.0) {
    return (0.0, 0.0);
  }
  return (
    inertHeadroom * (fN2 / fInertTotal),
    inertHeadroom * (fHe / fInertTotal),
  );
}
