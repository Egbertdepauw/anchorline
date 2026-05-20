/// Shared "is this gas safe at this depth?" readout used by the
/// gases editor (per-gas status line) and the segments editor
/// (per-row warning + dropdown filter).
///
/// Thresholds match the diver's mental model rather than the planner's
/// internal MOD table:
///   * green   — PPO2 ≤ 1.1   AND END ≤ 30 m
///   * amber   — 1.1 < PPO2 ≤ 1.51, OR END > 30 m
///   * red     — PPO2 > 1.51
///
/// The "is selectable in a segment dropdown" cutoff is PPO2 ≤ 1.61 —
/// a hair above the 1.6 limit used by the bailout / deco planner, so a
/// gas that just kisses 1.6 at the chosen depth is still pickable.
library;

import 'package:flutter/material.dart';

import '../../data/models/dive.dart' show DiveGasMix;
import '../../data/models/dive_plan.dart' show DivePlanGas;

const double _kSurfaceAtm = 1.013;

class GasSafetyReadout {
  const GasSafetyReadout({
    required this.text,
    required this.color,
    required this.isUnsafe,
    required this.isWarning,
  });

  /// The displayable status line (e.g. "MOD 33 m · END 30 m · OC PPO₂ 1.28").
  final String text;

  /// Colour the consuming widget should paint the text in.
  final Color color;

  /// True when the configuration is hard-unsafe (PPO₂ > 1.51 at depth).
  final bool isUnsafe;

  /// True when the configuration is borderline (PPO₂ > 1.1 at depth,
  /// or END > 30 m).
  final bool isWarning;
}

const _statusSuccess = Color(0xFF4ADE80);
const _statusWarning = Color(0xFFF39C12);
const _statusDanger = Color(0xFFE74C3C);
const _textSecondary = Color(0xFFA0AEB6);

/// OC PPO₂ of [gas] at [depthMeters]. Independent of CCR setpoint — the
/// safety logic is about "if you breathed this open-circuit at this
/// depth, what's the PPO₂", which is what matters when picking a
/// diluent for a CCR bailout.
double ocPpo2At(DivePlanGas gas, double depthMeters) {
  final fO2 = gas.oxygenPercent / 100.0;
  return fO2 * (_kSurfaceAtm + depthMeters / 10.0);
}

/// Equivalent Narcotic Depth (m) at [depthMeters] on [gas]. Treats O₂
/// as non-narcotic — the conservative convention used elsewhere in the
/// app for diluent / bailout planning.
double endAt(DivePlanGas gas, double depthMeters) {
  final fHe = gas.heliumPercent / 100.0;
  final end = (depthMeters + 10.0) * (1.0 - fHe) - 10.0;
  return end < 0 ? 0 : end;
}

/// Cap on PPO₂ for a gas to remain *selectable* on a given segment.
/// A hair above 1.6 so a deco gas right at its MOD stays pickable.
const double kSegmentGasPpo2HardCap = 1.61;

/// Whether [gas] should remain in the segment's gas dropdown at
/// [depthMeters]. Used to filter unsafe picks out of the picker.
bool isGasSelectableAt(DivePlanGas gas, double depthMeters) =>
    ocPpo2At(gas, depthMeters) <= kSegmentGasPpo2HardCap;

/// Compute the safety readout for [gas] at the deepest planned usage
/// depth [evaluatedDepth] (or null when the gas isn't bound to any
/// time>0 segment yet — then the readout shows MOD / END at MOD but
/// no PPO₂ figure or per-segment classification).
GasSafetyReadout? computeGasSafetyReadout(
    DivePlanGas gas, double? evaluatedDepth) {
  final fO2 = gas.oxygenPercent / 100.0;
  final fHe = gas.heliumPercent / 100.0;
  if (fO2 <= 0) return null;

  // MOD via the conventional cap (PPO₂ 1.4 on trimix, 1.6 on nitrox).
  final modCapPpo2 = gas.heliumPercent > 0 ? 1.4 : 1.6;
  final modMeters = ((modCapPpo2 / fO2) - 1.0) * 10.0;

  // END at the evaluated depth — when unset, fall back to MOD so the
  // chip still has a number to show.
  final endRefDepth = evaluatedDepth ?? modMeters;
  final endAtRef = (endRefDepth + 10.0) * (1.0 - fHe) - 10.0;

  final parts = <String>[];
  parts.add('MOD ${modMeters.toStringAsFixed(0)} m');
  parts.add(
    'END ${endAtRef.clamp(0, 200).toStringAsFixed(0)} m'
    '${evaluatedDepth == null ? "" : " @ ${evaluatedDepth.toStringAsFixed(0)} m"}',
  );

  bool isUnsafe = false;
  bool isWarning = false;
  double? ppo2;
  if (evaluatedDepth != null) {
    ppo2 = fO2 * (_kSurfaceAtm + evaluatedDepth / 10.0);
    parts.add('OC PPO₂ ${ppo2.toStringAsFixed(2)}');
    if (ppo2 > 1.51) {
      isUnsafe = true;
    } else if (ppo2 > 1.1 || endAtRef > 30) {
      isWarning = true;
    }
  } else if (endAtRef > 30) {
    isWarning = true;
  }

  String tail = '';
  if (isUnsafe && ppo2 != null) {
    tail = '  ⚠ PPO₂ $ppo2 exceeds 1.51 at '
        '${evaluatedDepth!.toStringAsFixed(0)} m';
  } else if (isWarning && ppo2 != null && ppo2 > 1.1) {
    tail = '  ⚠ PPO₂ too high to flush';
  } else if (isWarning && endAtRef > 30 && gas.heliumPercent > 0) {
    tail = '  ⚠ END above 30 m';
  }

  // Hypoxic flag is informational only — a hypoxic mix used at depth
  // where PPO₂ is in range is FINE (that's the point of a deep trimix
  // diluent). We surface the note but it does NOT push the colour to
  // amber on its own. The diver's actual safety at depth is what
  // determines the chip colour.
  final hypoxicSurfaceRisk = fO2 < 0.18;
  if (hypoxicSurfaceRisk) {
    parts.add('hypoxic — not safe near surface');
  }

  Color color;
  if (isUnsafe) {
    color = _statusDanger;
  } else if (isWarning) {
    color = _statusWarning;
  } else if (evaluatedDepth != null) {
    // Active in the plan AND safe at that depth → green, even if the
    // mix is hypoxic (deep trimix diluent used only at depth).
    color = _statusSuccess;
  } else {
    color = _textSecondary;
  }

  return GasSafetyReadout(
    text: '${parts.join(' · ')}$tail',
    color: color,
    isUnsafe: isUnsafe,
    isWarning: isWarning,
  );
}

/// Convenience for converting [DivePlanGas] → [DiveGasMix] in tests +
/// other surfaces that prefer the analysis-layer type.
DiveGasMix toDiveGasMix(DivePlanGas g) => DiveGasMix(
      oxygenPercent: g.oxygenPercent,
      heliumPercent: g.heliumPercent,
      isDiluent: g.isDiluent,
    );
