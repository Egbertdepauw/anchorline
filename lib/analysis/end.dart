/// Per-sample equivalent narcotic depth (END) for the active gas mix
/// at each sample. Two formulas:
///
/// **Formula A** (`countsOxygen == true`, default): N₂ + O₂ both narcotic.
///   END(m) = max(0, (depth + 10) × (1 − He fraction) − 10)
///
/// **Formula B** (`countsOxygen == false`, GUE/DIR): only N₂ narcotic.
///   END(m) = max(0, (depth + 10) × (N₂ / 0.79) − 10)
library;

import 'dart:typed_data';

import '../data/models/dive.dart' show DiveGasMix;

/// END colour-band thresholds (m).
const double kEndOrangeThreshold = 30.0;
const double kEndRedThreshold = 40.0;

enum EndBand { green, orange, red }

EndBand endBand(double endMeters) {
  if (endMeters >= kEndRedThreshold) return EndBand.red;
  if (endMeters >= kEndOrangeThreshold) return EndBand.orange;
  return EndBand.green;
}

/// Per-sample END (m) at each depth. Walks [depthMeters] and [gasMixIndex]
/// in parallel; pre-computes the narcotic factor once per mix.
///
/// [countsOxygen] selects the formula:
/// - `true`  — N₂ + O₂ narcotic (US-Navy/TDI convention)
/// - `false` — N₂ only narcotic (GUE/DIR convention)
Float32List computeEndSeries({
  required Float32List depthMeters,
  required Uint8List gasMixIndex,
  required List<DiveGasMix> gasMixes,
  required bool countsOxygen,
}) {
  assert(depthMeters.length == gasMixIndex.length);
  final out = Float32List(depthMeters.length);
  // Pre-compute the narcotic factor per mix.
  final factorByMix = Float32List(gasMixes.length);
  for (var i = 0; i < gasMixes.length; i++) {
    final he = gasMixes[i].heliumPercent / 100.0;
    if (countsOxygen) {
      factorByMix[i] = 1.0 - he;
    } else {
      final n2 = 1.0 - (gasMixes[i].oxygenPercent / 100.0) - he;
      factorByMix[i] = n2 / 0.79;
    }
  }
  for (var i = 0; i < depthMeters.length; i++) {
    final mixIdx = gasMixIndex[i];
    if (mixIdx >= factorByMix.length) {
      out[i] = double.nan;
      continue;
    }
    final end = (depthMeters[i] + 10.0) * factorByMix[mixIdx] - 10.0;
    out[i] = end < 0 ? 0.0 : end;
  }
  return out;
}
