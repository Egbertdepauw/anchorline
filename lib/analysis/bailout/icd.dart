/// Isobaric Counterdiffusion (ICD) detection for OC bailout gas switches.
///
/// When a diver switches from a helium-rich mix to a helium-poor (or
/// nitrogen-rich) mix, helium diffuses out of tissues faster than
/// nitrogen diffuses in, causing transient inner-ear supersaturation
/// that can trigger vestibular DCS. Doolette & Mitchell's "5:1 rule":
/// at any gas switch, ΔO₂ ≤ |ΔHe| / 5. If the inhaled-gas O₂ fraction
/// rises by more than one part for every five parts of helium dropped,
/// the switch carries ICD risk.
///
/// Severity classification used here:
///   - none      : ratio ≤ 0.2 (within the 5:1 rule) OR helium isn't
///                 actually dropping (we only flag He-rich → He-poor).
///   - marginal  : 0.2 < ratio AND |ΔHe| < 20 percentage points.
///                 Breaks 5:1 but the absolute helium gradient is small.
///   - severe    : ratio > 0.2 AND |ΔHe| ≥ 20 percentage points.
///                 Both the rule and the absolute He drop are large
///                 enough to make vestibular hits a real concern.
library;

import '../../data/models/dive.dart' show DiveGasMix;
import 'ascent_simulator.dart' show AscentStop;

enum IcdSeverity { none, marginal, severe }

class IcdRisk {
  final DiveGasMix fromGas;
  final DiveGasMix toGas;

  /// Depth (m) at which the switch occurs.
  final double switchDepthMeters;
  final IcdSeverity severity;

  /// Percentage-point change in O₂ (e.g. +29 means 21% → 50%).
  final int deltaO2;

  /// Percentage-point change in He (negative when He drops).
  final int deltaHe;

  const IcdRisk({
    required this.fromGas,
    required this.toGas,
    required this.switchDepthMeters,
    required this.severity,
    required this.deltaO2,
    required this.deltaHe,
  });
}

/// Severity of switching directly from [from] to [to]. Useful for
/// row-by-row UI tinting where the caller already has the gas pair.
IcdSeverity icdSeverityBetween(DiveGasMix from, DiveGasMix to) {
  return _severityFor(
    deltaO2: to.oxygenPercent - from.oxygenPercent,
    deltaHe: to.heliumPercent - from.heliumPercent,
  );
}

/// Walks [stops] in ascent order and returns one [IcdRisk] per
/// flagged gas switch. Switches with [IcdSeverity.none] are omitted.
List<IcdRisk> detectIcdRisks(List<AscentStop> stops) {
  final out = <IcdRisk>[];
  DiveGasMix? prev;
  for (final stop in stops) {
    final gas = stop.gas;
    if (prev != null && gas != prev) {
      final deltaO2 = gas.oxygenPercent - prev.oxygenPercent;
      final deltaHe = gas.heliumPercent - prev.heliumPercent;
      final severity = _severityFor(deltaO2: deltaO2, deltaHe: deltaHe);
      if (severity != IcdSeverity.none) {
        out.add(IcdRisk(
          fromGas: prev,
          toGas: gas,
          switchDepthMeters: stop.depthStartMeters,
          severity: severity,
          deltaO2: deltaO2,
          deltaHe: deltaHe,
        ));
      }
    }
    prev = gas;
  }
  return out;
}

IcdSeverity _severityFor({required int deltaO2, required int deltaHe}) {
  // Only He-dropping, O₂-rising switches carry ICD risk.
  if (deltaHe >= 0 || deltaO2 <= 0) return IcdSeverity.none;
  final ratio = deltaO2 / -deltaHe;
  if (ratio <= 0.2) return IcdSeverity.none;
  return -deltaHe >= 20 ? IcdSeverity.severe : IcdSeverity.marginal;
}
