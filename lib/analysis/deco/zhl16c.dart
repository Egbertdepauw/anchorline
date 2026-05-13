/// ZHL-16C + Erik-Baker-GF replay engine. Walks samples one interval at
/// a time, updating each of 16 N2 + 16 He tissue compartments via the
/// Schreiner equation. Per-sample GF99 = current supersaturation as a
/// percentage of the allowed M-value gradient at that depth.
library;

import 'dart:math';
import 'dart:typed_data';

import '../../data/models/dive.dart' show DiveGasMix;
import 'replay_result.dart';
import 'schreiner.dart';
import 'tissue_model.dart';

/// Minimal interface for what the engine needs from a sample stream.
abstract class SampleStream {
  Float32List get depthMeters;
  Uint8List get gasMixIndex;
  int get sampleIntervalMs;
}

class SampleStub implements SampleStream {
  @override
  final Float32List depthMeters;
  @override
  final Uint8List gasMixIndex;
  @override
  final int sampleIntervalMs;
  SampleStub({
    required this.depthMeters,
    required this.gasMixIndex,
    required this.sampleIntervalMs,
  });
}

const double _waterVapourPressureBar = 0.0627;
const double _surfaceAtmBar = 1.013;

class Zhl16cReplay {
  DecoReplayResult run({
    required SampleStream samples,
    required List<DiveGasMix> gasMixes,
    required int gfLow,
    required int gfHigh,
  }) {
    final n = samples.depthMeters.length;
    final gf99 = Float32List(n);
    final ceiling = Float32List(n);
    final tissueLoads = List<Float32List>.generate(
      16,
      (_) => Float32List(n),
      growable: false,
    );

    // Initialise compartments to surface equilibrium on air.
    final pN2 = List<double>.generate(
      16,
      (_) => (_surfaceAtmBar - _waterVapourPressureBar) * 0.79,
    );
    final pHe = List<double>.filled(16, 0.0);

    // Use integer truncation matching how the Schreiner call works —
    // a sub-second interval rounds to 0 and loadCompartment returns the
    // current load unchanged, which is correct.
    final intervalSec = samples.sampleIntervalMs ~/ 1000;
    double maxGf99 = 0.0;

    for (var i = 0; i < n; i++) {
      final depth = samples.depthMeters[i];
      final ambientBar = _surfaceAtmBar + depth / 10.0;

      final mix =
          gasMixes[samples.gasMixIndex[i].clamp(0, gasMixes.length - 1)];
      final fO2 = mix.oxygenPercent / 100.0;
      final fHe = mix.heliumPercent / 100.0;
      final fN2 = 1.0 - fO2 - fHe;
      final paN2 = (ambientBar - _waterVapourPressureBar) * fN2;
      final paHe = (ambientBar - _waterVapourPressureBar) * fHe;

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

      double worstGf = 0;
      double worstCeiling = 0;
      for (var c = 0; c < 16; c++) {
        final totalLoad = pN2[c] + pHe[c];
        final tissueN2Frac = pN2[c] / max(totalLoad, 1e-9);
        final tissueHeFrac = 1.0 - tissueN2Frac;
        final a = zhl16cTissues[c].aN2 * tissueN2Frac +
            zhl16cTissues[c].aHe * tissueHeFrac;
        final b = zhl16cTissues[c].bN2 * tissueN2Frac +
            zhl16cTissues[c].bHe * tissueHeFrac;
        // GF99 (Subsurface definition): what GF would you hit if you surfaced
        // right now? Evaluated against the surface M-value, not depth M-value.
        // This is always meaningful — it rises as tissues load up.
        final mSurface = a + _surfaceAtmBar / b;
        final allowedSurface = mSurface - _surfaceAtmBar;
        final supersatSurface = totalLoad - _surfaceAtmBar;
        final gf =
            allowedSurface > 0 ? (supersatSurface / allowedSurface) * 100.0 : 0.0;
        if (gf > worstGf) worstGf = gf;
        // tissueLoadsPct: load as % of current M-value at ambient depth.
        final mValueAtDepth = a + ambientBar / b;
        tissueLoads[c][i] = (totalLoad / mValueAtDepth * 100.0);
        // Ceiling: depth at which tissue load hits the M-value line.
        final pCeilingBar = (totalLoad - a) * b;
        final ceilingForC = (pCeilingBar - _surfaceAtmBar) * 10.0;
        if (ceilingForC > worstCeiling) worstCeiling = ceilingForC;
      }
      gf99[i] = worstGf;
      ceiling[i] = worstCeiling < 0 ? 0 : worstCeiling;
      if (worstGf > maxGf99) maxGf99 = worstGf;
    }

    // Surface GF: re-evaluate all compartments at surface pressure.
    double surfaceGf = 0;
    for (var c = 0; c < 16; c++) {
      final totalLoad = pN2[c] + pHe[c];
      final tissueN2Frac = pN2[c] / max(totalLoad, 1e-9);
      final tissueHeFrac = 1.0 - tissueN2Frac;
      final a = zhl16cTissues[c].aN2 * tissueN2Frac +
          zhl16cTissues[c].aHe * tissueHeFrac;
      final b = zhl16cTissues[c].bN2 * tissueN2Frac +
          zhl16cTissues[c].bHe * tissueHeFrac;
      final mSurface = a + _surfaceAtmBar / b;
      final allowed = mSurface - _surfaceAtmBar;
      final supersat = totalLoad - _surfaceAtmBar;
      final gf = allowed > 0 ? (supersat / allowed) * 100.0 : 0.0;
      if (gf > surfaceGf) surfaceGf = gf;
    }

    return DecoReplayResult(
      gf99Series: gf99,
      ceilingMeters: ceiling,
      tissueLoadsPct: tissueLoads,
      surfaceGfFinal: surfaceGf,
      maxGf99: maxGf99,
      algorithm: DecoAlgorithm.zhl16c,
      gfLow: gfLow,
      gfHigh: gfHigh,
    );
  }
}
