/// Bailout ascent simulator. Thin shim over [planDeco]: calls the deco
/// planner to produce the ladder of stops + ascent legs, then decorates
/// each leg with gas-volume math using bottom/deco SAC.
///
/// Public API ([AscentPlan], [AscentStop], [simulateAscent]) is unchanged
/// so the bailout planner doesn't need to know about [DecoStep].
library;

import 'package:subsurface_core/data/models/dive.dart' show DiveGasMix;
import '../deco/deco_planner.dart' show planDeco;

// ---------------------------------------------------------------------------
// Public data types
// ---------------------------------------------------------------------------

/// A single leg of the ascent plan: either a flat deco stop
/// (depthStart == depthEnd) or a moving ascent segment.
class AscentStop {
  final double depthStartMeters;
  final double depthEndMeters;
  final Duration duration;
  final DiveGasMix gas;
  final double volumeLitresConsumed;

  /// CCR loop setpoint (bar) the diver is holding on this leg. Null or
  /// ≤ 0.1 means open circuit — the renderer falls back to fO2 × ambient
  /// for displayed PPO2 and to the gas's own inert fractions for density.
  /// Setting this lets the dive-plan output show CCR setpoints without
  /// the OC bailout code paths needing to care.
  final double? setpointBar;

  const AscentStop({
    required this.depthStartMeters,
    required this.depthEndMeters,
    required this.duration,
    required this.gas,
    required this.volumeLitresConsumed,
    this.setpointBar,
  });

  /// True when this leg is a flat deco hold.
  bool get isStop => depthStartMeters == depthEndMeters;
}

/// The full ascent plan returned by [simulateAscent].
class AscentPlan {
  final List<AscentStop> stops;
  final Duration totalTime;

  /// Gas consumption keyed by mix. Sum of values equals sum of
  /// [AscentStop.volumeLitresConsumed] across all [stops].
  final Map<DiveGasMix, double> volumeByGas;

  const AscentPlan({
    required this.stops,
    required this.totalTime,
    required this.volumeByGas,
  });
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const double _surfaceAtmBar = 1.013;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Simulate an open-circuit bailout ascent from [triggerDepthMeters].
///
/// Delegates the deco math to [planDeco] (ZHL-16C + Erik-Baker GF, 3m
/// stops, GF-Low-determined first stop, linearly-interpolated GF between
/// stops). This function adds gas-volume math: bottomSAC × ambient ×
/// duration on the ascent from trigger to the first stop, decoSAC ×
/// ambient × duration everywhere thereafter.
///
/// PPO2 limits are hardcoded to 1.6 for both the bottom mix and deco
/// switches — the user-facing GUE option (1.4) lives at the bailout
/// planner layer (it affects which mixes get added to [availableGases],
/// not the safety gate inside the simulator).
AscentPlan simulateAscent({
  required double triggerDepthMeters,
  required List<double> initialN2Bar,
  required List<double> initialHeBar,
  required List<DiveGasMix> availableGases,
  required int gfLow,
  required int gfHigh,
  required int ascentRateFast,
  required int ascentRateSlow,
  required int sacBottom,
  required int sacDeco,
}) {
  assert(initialN2Bar.length == 16, 'initialN2Bar must have 16 elements');
  assert(initialHeBar.length == 16, 'initialHeBar must have 16 elements');
  assert(availableGases.isNotEmpty, 'availableGases must not be empty');

  final steps = planDeco(
    initialN2Bar: initialN2Bar,
    initialHeBar: initialHeBar,
    triggerDepthMeters: triggerDepthMeters,
    gases: availableGases,
    gfLow: gfLow,
    gfHigh: gfHigh,
    ascentRateFastMPerMin: ascentRateFast,
    ascentRateSlowMPerMin: ascentRateSlow,
    ppo2LimitBottom: 1.6,
    ppo2LimitDeco: 1.6,
  );

  // NDL dive: planDeco returns [] → one straight-up leg at the slow rate
  // on the bottom mix so the bailout volume math still produces a number.
  // Uses sacBottom: the user's rule is that bottom SAC applies until the
  // first deco-or-gas-switch stop. With no stops at all (true NDL), the
  // diver is in bottom-phase mindset the whole way up — bottom SAC.
  if (steps.isEmpty) {
    final secs = (triggerDepthMeters / ascentRateSlow * 60).round();
    final gas = availableGases.first;
    final avgAmbient = _surfaceAtmBar + triggerDepthMeters / 20.0;
    final volumeL = sacBottom * avgAmbient * (secs / 60);
    return AscentPlan(
      stops: [
        AscentStop(
          depthStartMeters: triggerDepthMeters,
          depthEndMeters: 0,
          duration: Duration(seconds: secs),
          gas: gas,
          volumeLitresConsumed: volumeL,
        ),
      ],
      totalTime: Duration(seconds: secs),
      volumeByGas: {gas: volumeL},
    );
  }

  // Decorate each DecoStep with gas volume. Bottom SAC applies until we
  // first hit a flat stop; deco SAC applies from that point on.
  var inDecoZone = false;
  final stops = <AscentStop>[];
  final volumeByGas = <DiveGasMix, double>{};
  var totalTime = Duration.zero;
  for (final step in steps) {
    if (step.isStop) inDecoZone = true;
    final sac = inDecoZone ? sacDeco : sacBottom;
    final avgAmbient =
        _surfaceAtmBar + (step.depthStartMeters + step.depthEndMeters) / 20.0;
    final minutes = step.duration.inMilliseconds / 60000.0;
    final volumeL = sac * avgAmbient * minutes;
    stops.add(AscentStop(
      depthStartMeters: step.depthStartMeters,
      depthEndMeters: step.depthEndMeters,
      duration: step.duration,
      gas: step.gas,
      volumeLitresConsumed: volumeL,
    ));
    volumeByGas[step.gas] = (volumeByGas[step.gas] ?? 0.0) + volumeL;
    totalTime += step.duration;
  }
  return AscentPlan(stops: stops, totalTime: totalTime, volumeByGas: volumeByGas);
}
