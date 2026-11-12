/// Compute the instantaneous CCR loop-gas composition (O₂, He, N₂
/// fractions) at a given depth and setpoint.
///
/// On a closed-circuit rebreather the diver doesn't actually breathe the
/// diluent — they breathe a *loop* mixture whose O₂ partial pressure is
/// held at the setpoint by the unit's solenoid. The inert fraction
/// (everything that isn't O₂) is filled by the diluent, with the same
/// He : N₂ ratio the diluent had.
///
/// So at depth D, setpoint S, ambient P = atm + D/10:
///
///   loopO2 = S / P                       (PPO₂ regulated)
///   loopInert = 1 − loopO2
///   loopHe = loopInert × dilHe / (dilHe + dilN2)
///   loopN2 = loopInert × dilN2 / (dilHe + dilN2)
///
/// This is what the dive computer displays as "current gas" during a CCR
/// dive — e.g. a Petrel 3 on a 22/41 diluent with setpoint 1.4 at 55 m
/// shows 21/41 (loopO2≈21 %, loopHe≈41 %).
///
/// Pre-app-2026-05-19 the app used the diluent's STATIC composition for
/// density / END / narcosis math, which got the He fraction roughly
/// right but the O₂ fraction badly wrong (especially shallow, where
/// loopO2 can climb to 40 %+). For CCR samples downstream of this
/// helper, use the returned loop fractions instead.
library;

import 'package:subsurface_core/data/models/dive.dart' show DiveGasMix;

/// One sample of CCR loop-gas composition. All fractions are 0.0–1.0.
class LoopGasFractions {
  final double o2Fraction;
  final double heFraction;
  final double n2Fraction;
  const LoopGasFractions(this.o2Fraction, this.heFraction, this.n2Fraction);
}

/// Compute the loop gas at one sample.
///
/// [depthMeters] — depth in metres (≥ 0).
/// [ppo2Bar] — the LIVE / measured PPO₂ in bar (the voted average of the
///   cell readings, ideally). When voted PPO₂ isn't available the
///   setpoint is a reasonable fallback, but voted is more accurate
///   during setpoint transitions, solenoid lag, and dil flushes. Must
///   be > 0; when the dive computer's recorded value is 0 (e.g. surface
///   or OC bailout), this helper isn't the right tool — fall back to
///   the static gas mix at the sample's `gasMixIndex` instead.
/// [diluent] — the diluent mix (the one with `isDiluent == true`).
/// [atmosphericPressureBar] — surface atmospheric pressure, default 1.013.
///
/// Returned fractions are clamped so that [o2Fraction] ∈ [0, 1].
/// Edge cases:
///   - At very shallow depth with a high PPO₂, loopO2 can exceed 1.0
///     mathematically; we clamp at 1.0 and zero-out the inert fractions
///     (the diver is on pure O₂, no inert).
///   - When the diluent has no inert content (degenerate case), He and
///     N₂ are both returned as 0.
LoopGasFractions loopGasAt({
  required double depthMeters,
  required double ppo2Bar,
  required DiveGasMix diluent,
  double atmosphericPressureBar = 1.013,
}) {
  final ambBar = atmosphericPressureBar + depthMeters / 10.0;
  final loopO2 = (ppo2Bar / ambBar).clamp(0.0, 1.0);

  final dilHe = diluent.heliumPercent / 100.0;
  final dilO2 = diluent.oxygenPercent / 100.0;
  final dilN2 = 1.0 - dilO2 - dilHe;
  final dilInert = dilHe + dilN2;

  if (dilInert <= 0 || loopO2 >= 1.0) {
    return LoopGasFractions(loopO2, 0.0, 0.0);
  }

  final inert = 1.0 - loopO2;
  final loopHe = inert * (dilHe / dilInert);
  final loopN2 = inert * (dilN2 / dilInert);
  return LoopGasFractions(loopO2, loopHe, loopN2);
}

/// Convenience: index of the first diluent mix in [gasMixes], or null if
/// none. Used by density / END calcs to know whether a CCR sample's
/// per-sample [gasMixIndex] should be overridden by a live loop-gas
/// computation against the diluent.
int? diluentIndex(List<DiveGasMix> gasMixes) {
  for (var i = 0; i < gasMixes.length; i++) {
    if (gasMixes[i].isDiluent) return i;
  }
  return null;
}

/// The "deepest" diluent in [gasMixes] — the one with the LOWEST O₂
/// fraction (= highest He, most depth-tolerant). Used by density / END
/// as the loop-gas fallback when the sample's own `gasMixIndex` points
/// at a non-diluent (e.g. Subsurface mis-recorded a gaschange event on
/// a CCR dive to a deco / bailout cylinder the diver never actually
/// breathed). Picking the deepest diluent here matches the user's
/// actual breathing gas at depth, and at shallower points it gives
/// slightly-too-low density — which the max-density / max-END stats
/// don't care about anyway.
///
/// Returns null when no diluent exists (pure-OC dive — caller should
/// fall back to static gas at gasMixIndex).
DiveGasMix? deepestDiluent(List<DiveGasMix> gasMixes) {
  DiveGasMix? best;
  for (final m in gasMixes) {
    if (!m.isDiluent) continue;
    if (best == null || m.oxygenPercent < best.oxygenPercent) best = m;
  }
  return best;
}
