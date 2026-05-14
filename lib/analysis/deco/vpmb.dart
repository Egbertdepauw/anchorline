/// VPM-B replay engine. v1 implementation uses ZHL-16C compartment
/// loading combined with a conservatism-reduced allowed-gradient
/// scheme (see vpmb_constants.dart). The output type and call shape
/// match Zhl16cReplay so DecoReplayEngine can dispatch transparently.
///
/// NOTE: This is a v1 approximation — not a faithful Subsurface VPM-B
/// port. A proper VPM-B implementation regenerates bubble nucleation
/// radii per ascent phase; that refinement can be layered on later if
/// divergence from Shearwater's / Subsurface's VPM-B becomes
/// user-visible in practice.
library;

import 'dart:math';
import 'dart:typed_data';

import '../../data/models/dive.dart' show DiveGasMix;
import 'gas_pressures.dart';
import 'replay_result.dart';
import 'schreiner.dart';
import 'tissue_model.dart';
import 'vpmb_constants.dart';
import 'zhl16c.dart' show SampleStream;

const double _surfaceAtmBar = 1.013;

class VpmbReplay {
  /// [triggerSampleIdx] — same semantics as [Zhl16cReplay.run]: when
  /// non-null, capture tissue state at that sample for bailout planning.
  DecoReplayResult run({
    required SampleStream samples,
    required List<DiveGasMix> gasMixes,
    required int conservatism,
    int? triggerSampleIdx,
  }) {
    final n = samples.depthMeters.length;
    final gf99 = Float32List(n);
    final ceiling = Float32List(n);
    final tissueLoads = List<Float32List>.generate(
      16,
      (_) => Float32List(n),
      growable: false,
    );

    final pN2 = List<double>.generate(16, (_) => surfaceEquilibriumN2Bar);
    final pHe = List<double>.filled(16, 0.0);

    final intervalSec = samples.sampleIntervalMs ~/ 1000;
    final allowedFactor = vpmbGradientFactor(conservatism);
    double maxGf99 = 0.0;

    double maxDepthSoFar = -1;
    List<double> peakN2 = List<double>.from(pN2);
    List<double> peakHe = List<double>.from(pHe);
    List<double>? triggerN2;
    List<double>? triggerHe;

    for (var i = 0; i < n; i++) {
      final depth = samples.depthMeters[i];
      final ambientBar = _surfaceAtmBar + depth / 10.0;
      final mix =
          gasMixes[samples.gasMixIndex[i].clamp(0, gasMixes.length - 1)];
      final (paN2, paHe) = inertPartialPressures(
        ambientBar: ambientBar,
        mix: mix,
        setpointBar: samples.setpointBar[i],
      );

      for (var c = 0; c < 16; c++) {
        pN2[c] = loadCompartment(
          currentLoadBar: pN2[c],
          inertGasPartialPressureBar: paN2,
          halfTimeMin: zhl16cTissues[c].halfTimeN2Min,
          intervalSeconds: intervalSec,
        );
        pHe[c] = loadCompartment(
          currentLoadBar: pHe[c],
          inertGasPartialPressureBar: paHe,
          halfTimeMin: zhl16cTissues[c].halfTimeHeMin,
          intervalSeconds: intervalSec,
        );
      }

      double worstGfSurface = 0;
      double worstCeiling = 0;
      for (var c = 0; c < 16; c++) {
        final totalLoad = pN2[c] + pHe[c];
        final tissueN2Frac = pN2[c] / max(totalLoad, 1e-9);
        final tissueHeFrac = 1.0 - tissueN2Frac;
        final a = zhl16cTissues[c].aN2 * tissueN2Frac +
            zhl16cTissues[c].aHe * tissueHeFrac;
        final b = zhl16cTissues[c].bN2 * tissueN2Frac +
            zhl16cTissues[c].bHe * tissueHeFrac;

        // VPM-B-style allowed gradient: scale the Bühlmann surface
        // gradient by allowedFactor. At level 0 this equals the full
        // Bühlmann limit; at level 4 it is halved (more conservative).
        final mSurface = a + _surfaceAtmBar / b;
        final allowedSurface = (mSurface - _surfaceAtmBar) * allowedFactor;
        final supersatSurface = totalLoad - _surfaceAtmBar;
        final gf = allowedSurface > 0
            ? (supersatSurface / allowedSurface) * 100.0
            : 0.0;
        if (gf > worstGfSurface) worstGfSurface = gf;

        // tissueLoadsPct: load as % of current at-depth M-value.
        final mValueAtDepth = a + ambientBar / b;
        tissueLoads[c][i] = ((totalLoad / mValueAtDepth) * 100.0).toDouble();

        // Ceiling: depth at which load equals the allowed gradient limit.
        // load = a + (P_ceil / b) × allowedFactor
        // → P_ceil = (load - a) × b / allowedFactor
        // (Approximation — true VPM-B ceiling is derived from bubble radii.)
        final pCeilingBar = allowedFactor > 0
            ? (totalLoad - a) * b / allowedFactor
            : ambientBar;
        final ceilingForC = (pCeilingBar - _surfaceAtmBar) * 10.0;
        if (ceilingForC > worstCeiling) worstCeiling = ceilingForC;
      }
      gf99[i] = worstGfSurface;
      ceiling[i] = worstCeiling < 0 ? 0 : worstCeiling;
      if (worstGfSurface > maxGf99) maxGf99 = worstGfSurface;

      if (depth > maxDepthSoFar) {
        maxDepthSoFar = depth;
        peakN2 = List<double>.from(pN2);
        peakHe = List<double>.from(pHe);
      }
      if (triggerSampleIdx != null && i == triggerSampleIdx) {
        triggerN2 = List<double>.from(pN2);
        triggerHe = List<double>.from(pHe);
      }
    }

    return DecoReplayResult(
      gf99Series: gf99,
      ceilingMeters: ceiling,
      tissueLoadsPct: tissueLoads,
      surfaceGfFinal: gf99.isNotEmpty ? gf99.last : 0.0,
      maxGf99: maxGf99,
      algorithm: DecoAlgorithm.vpmb,
      vpmbConservatism: conservatism,
      finalN2Bar: List<double>.unmodifiable(pN2),
      finalHeBar: List<double>.unmodifiable(pHe),
      peakDepthN2Bar: List<double>.unmodifiable(peakN2),
      peakDepthHeBar: List<double>.unmodifiable(peakHe),
      triggerN2Bar:
          triggerN2 == null ? const [] : List<double>.unmodifiable(triggerN2),
      triggerHeBar:
          triggerHe == null ? const [] : List<double>.unmodifiable(triggerHe),
    );
  }
}
