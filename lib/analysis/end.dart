/// Per-sample equivalent narcotic depth (END) for the active gas mix
/// at each sample. Two formulas:
///
/// **Formula A** (`countsOxygen == true`, default, **GUE / DIR**):
///   N₂ + O₂ both narcotic — the standard tech-diving convention,
///   used by GUE and most modern training agencies. O₂ is treated
///   as having narcotic potency equivalent to N₂.
///   END(m) = max(0, (depth + 10) × (1 − He fraction) − 10)
///
/// **Formula B** (`countsOxygen == false`, US Navy / older):
///   only N₂ narcotic. Older convention; some PADI / NAUI / TDI
///   tables still use this. Gives a shallower (more optimistic) END.
///   END(m) = max(0, (depth + 10) × (N₂ / 0.79) − 10)
library;

import 'dart:typed_data';

import '../data/models/dive.dart' show DiveGasMix;
import 'loop_gas.dart';

/// END colour-band thresholds (m).
const double kEndOrangeThreshold = 30.0;
const double kEndRedThreshold = 40.0;

enum EndBand { green, orange, red }

EndBand endBand(double endMeters) {
  if (endMeters >= kEndRedThreshold) return EndBand.red;
  if (endMeters >= kEndOrangeThreshold) return EndBand.orange;
  return EndBand.green;
}

/// Per-sample END (m) at each depth.
///
/// For OC samples (no setpoint, or no diluent in [gasMixes]) the END
/// is computed from the static gas mix at the sample's [gasMixIndex] —
/// the original behaviour.
///
/// For CCR samples (signalled by a positive [ppo2Bar] and the presence
/// of a diluent in [gasMixes]) the END uses the LIVE LOOP GAS at that
/// sample, derived from the diluent's inert composition + the
/// per-sample PPO₂. Previously CCR samples silently used whichever
/// static mix the parser assigned (often the OC bailout with no
/// helium), which gave END ≈ depth — i.e. wrong by 20–30 m on a
/// helium-rich dive.
///
/// [countsOxygen] selects the formula:
/// - `true`  — N₂ + O₂ both narcotic (GUE / DIR / standard tech)
/// - `false` — N₂ only narcotic (older US-Navy / some PADI tables)
///
/// [ppo2Bar] should be the per-sample VOTED / measured PPO₂ (not the
/// setpoint target) so cell drift / solenoid lag / dil flushes show
/// up correctly. Pass null for OC dives.
Float32List computeEndSeries({
  required Float32List depthMeters,
  required Uint8List gasMixIndex,
  required List<DiveGasMix> gasMixes,
  required bool countsOxygen,
  Float32List? ppo2Bar,
}) {
  assert(depthMeters.length == gasMixIndex.length);
  assert(ppo2Bar == null || ppo2Bar.length == depthMeters.length);
  final out = Float32List(depthMeters.length);
  // Pre-compute the narcotic factor per static mix (the OC fallback path).
  final factorByMix = Float32List(gasMixes.length);
  for (var i = 0; i < gasMixes.length; i++) {
    factorByMix[i] = _narcoticFactor(
      o2: gasMixes[i].oxygenPercent / 100.0,
      he: gasMixes[i].heliumPercent / 100.0,
      countsOxygen: countsOxygen,
    );
  }
  final diluentIdx = diluentIndex(gasMixes);
  final diluent = diluentIdx != null ? gasMixes[diluentIdx] : null;
  for (var i = 0; i < depthMeters.length; i++) {
    final live = ppo2Bar?[i] ?? 0.0;
    double factor;
    if (live > 0 && diluent != null) {
      final loop = loopGasAt(
        depthMeters: depthMeters[i],
        ppo2Bar: live,
        diluent: diluent,
      );
      factor = _narcoticFactor(
        o2: loop.o2Fraction,
        he: loop.heFraction,
        countsOxygen: countsOxygen,
      );
    } else {
      final mixIdx = gasMixIndex[i];
      if (mixIdx >= factorByMix.length) {
        out[i] = double.nan;
        continue;
      }
      factor = factorByMix[mixIdx];
    }
    final end = (depthMeters[i] + 10.0) * factor - 10.0;
    out[i] = end < 0 ? 0.0 : end;
  }
  return out;
}

double _narcoticFactor({
  required double o2,
  required double he,
  required bool countsOxygen,
}) {
  if (countsOxygen) {
    // N₂ + O₂ both narcotic — narcotic fraction = 1 − He.
    return 1.0 - he;
  }
  // N₂ only narcotic. Compare to air's N₂ fraction (0.79).
  final n2 = 1.0 - o2 - he;
  return n2 / 0.79;
}
