/// Schreiner equation — exponential approach to equilibrium for a
/// single tissue compartment over a single time interval.
///
/// Returns the new compartment load (bar) given:
/// - [currentLoadBar] — the existing dissolved inert-gas partial pressure
/// - [inertGasPartialPressureBar] — what's currently being breathed (PaN2 or PaHe)
/// - [halfTimeMin] — the compartment's half-time for this gas
/// - [intervalSeconds] — elapsed time in this state
///
/// For a constant-depth segment: P(t) = Pi + (P0 − Pi) × exp(−k·t)
/// where k = ln(2) / halfTime.
library;

import 'dart:math';

double loadCompartment({
  required double currentLoadBar,
  required double inertGasPartialPressureBar,
  required double halfTimeMin,
  required int intervalSeconds,
}) {
  if (intervalSeconds <= 0) return currentLoadBar;
  final k = ln2 / (halfTimeMin * 60.0);
  final t = intervalSeconds.toDouble();
  return inertGasPartialPressureBar +
      (currentLoadBar - inertGasPartialPressureBar) * exp(-k * t);
}
