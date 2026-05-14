import 'dart:typed_data';

enum DecoAlgorithm { zhl16c, vpmb }

class DecoReplayResult {
  /// Per-sample instantaneous gradient factor (%) — 0 at surface
  /// equilibrium, 100 at the limit, >100 means supersaturated.
  final Float32List gf99Series;

  /// Per-sample deco ceiling (m). 0 means "no stop required".
  final Float32List ceilingMeters;

  /// 16 series, one per ZHL-16C compartment, each = current load
  /// expressed as % of compartment's current M-value. >100 = supersaturated.
  final List<Float32List> tissueLoadsPct;

  /// What GF you'd hit if you surfaced at the last sample.
  final double surfaceGfFinal;

  /// Peak GF99 across the dive.
  final double maxGf99;

  /// Which algorithm produced this result.
  final DecoAlgorithm algorithm;

  /// VPM-B-specific input recorded for cache invalidation. Null for ZHL-16C.
  final int? vpmbConservatism;

  /// ZHL-16C-specific GF inputs recorded for cache invalidation. Both null for VPM-B.
  final int? gfLow;
  final int? gfHigh;

  /// Tissue compartment N2 partial pressures (bar) at the final sample.
  /// 16-element list, fast-to-slow.
  final List<double> finalN2Bar;

  /// Tissue compartment He partial pressures (bar) at the final sample.
  /// 16-element list, fast-to-slow.
  final List<double> finalHeBar;

  /// Tissue compartment N2 partial pressures (bar) at the deepest sample.
  /// 16-element list, fast-to-slow.
  final List<double> peakDepthN2Bar;

  /// Tissue compartment He partial pressures (bar) at the deepest sample.
  final List<double> peakDepthHeBar;

  /// Tissue compartment N2 partial pressures (bar) at the bailout trigger
  /// sample (caller-supplied; typically the latest sample at substantial
  /// depth). Multi-level dives have worst-case loading near the END of
  /// the bottom phase, not at the deepest moment. Empty when the caller
  /// didn't ask for a trigger snapshot.
  final List<double> triggerN2Bar;

  /// Tissue compartment He partial pressures (bar) at the trigger sample.
  final List<double> triggerHeBar;

  const DecoReplayResult({
    required this.gf99Series,
    required this.ceilingMeters,
    required this.tissueLoadsPct,
    required this.surfaceGfFinal,
    required this.maxGf99,
    required this.algorithm,
    this.vpmbConservatism,
    this.gfLow,
    this.gfHigh,
    this.finalN2Bar = const [],
    this.finalHeBar = const [],
    this.peakDepthN2Bar = const [],
    this.peakDepthHeBar = const [],
    this.triggerN2Bar = const [],
    this.triggerHeBar = const [],
  });
}
