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
  });
}
