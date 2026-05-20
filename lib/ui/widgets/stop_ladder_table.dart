/// StopLadderTable — shared per-stop ascent table widget.
///
/// Extracted from BailoutSection so the Dive Plan tab (and any other future
/// consumer) can render the same stop-ladder view without depending on the
/// full bailout result model.
library;

import 'package:flutter/material.dart';

import '../../analysis/bailout/ascent_simulator.dart' show AscentStop;
import '../../analysis/bailout/icd.dart'
    show IcdSeverity, icdSeverityBetween;
import '../../analysis/gas_density.dart' show mixDensityAt1Atm;
import '../../data/models/dive.dart' show DiveGasMix;
import '../theme/tokens.dart';

/// Per-stop ascent table. Adjacent minute-steps with the same gas and
/// same depth are consolidated into single rows for readability.
class StopLadderTable extends StatelessWidget {
  const StopLadderTable({
    super.key,
    required this.stops,
    required this.scheme,
    this.startingRuntime = Duration.zero,
    this.icdRedAccent = const Color(0xFFE74C3C),
    this.icdAmberAccent = const Color(0xFFF39C12),
  });

  final List<AscentStop> stops;
  final ColorScheme scheme;

  /// Dive runtime accumulated before the bailout trigger. The RUNTIME
  /// column counts up from here.
  final Duration startingRuntime;

  /// Colour used for severe ICD tints (default: statusDanger red).
  final Color icdRedAccent;

  /// Colour used for marginal ICD tints (default: statusWarning amber).
  final Color icdAmberAccent;

  // ── Row consolidation ────────────────────────────────────────────────
  //
  // The planner emits one leg per minute (1m ascents + 3m stop holds). The
  // diver wants a stop-oriented view a la MultiDeco: one row per stop, plus
  // a transit row whenever a meaningful ascent (trigger→first-stop and
  // final stop→surface) precedes/follows a stop. Intermediate inter-stop
  // 3m ascents fold into the *following* stop's volume since they're tiny
  // and not separately interesting.

  List<ConsolidatedStopRow> _consolidate() {
    final rows = <ConsolidatedStopRow>[];
    Duration ascentDuration = Duration.zero;
    double ascentVolume = 0.0;
    double ascentTargetDepth = 0;
    DiveGasMix? ascentGas;
    double? ascentSetpoint;
    var hasAscent = false;
    var seenAnyStop = false;

    for (final leg in stops) {
      final isRealStop = leg.isStop && leg.duration > Duration.zero;
      if (isRealStop) {
        // Only emit the trigger→first-stop transit as its own row. Inter-
        // stop ascents fold into the stop they precede so the table reads
        // as a clean stop ladder.
        if (hasAscent && !seenAnyStop) {
          rows.add(ConsolidatedStopRow.ascent(
            targetDepthMeters: ascentTargetDepth,
            gas: ascentGas!,
            volumeLitres: ascentVolume,
            travelDuration: ascentDuration,
            setpointBar: ascentSetpoint,
          ));
          ascentDuration = Duration.zero;
          ascentVolume = 0.0;
          hasAscent = false;
          ascentGas = null;
          ascentSetpoint = null;
        }
        rows.add(ConsolidatedStopRow.stop(
          depthMeters: leg.depthStartMeters,
          stopDuration: leg.duration,
          gas: leg.gas,
          // Fold pending inter-stop ascent volume into this stop so
          // nothing falls off the totals.
          volumeLitres: leg.volumeLitresConsumed + ascentVolume,
          setpointBar: leg.setpointBar,
        ));
        // Inter-stop ascent time gets attributed to the stop it preceded.
        // It's already in totalTime via the planner's sum.
        ascentDuration = Duration.zero;
        ascentVolume = 0.0;
        hasAscent = false;
        ascentGas = null;
        ascentSetpoint = null;
        seenAnyStop = true;
      } else if (!leg.isStop) {
        // Ascent leg. Track destination + accumulate. If the gas
        // changes mid-ascent (e.g. 67 m → 22 m on bottom mix then 22 m →
        // 15 m on EAN 50), emit the accumulated row first so each
        // displayed gas matches the leg it was actually breathed on.
        if (hasAscent && !seenAnyStop && ascentGas != leg.gas) {
          rows.add(ConsolidatedStopRow.ascent(
            targetDepthMeters: ascentTargetDepth,
            gas: ascentGas!,
            volumeLitres: ascentVolume,
            travelDuration: ascentDuration,
            setpointBar: ascentSetpoint,
          ));
          ascentDuration = Duration.zero;
          ascentVolume = 0.0;
          ascentGas = null;
          ascentSetpoint = null;
        }
        ascentDuration += leg.duration;
        ascentVolume += leg.volumeLitresConsumed;
        ascentTargetDepth = leg.depthEndMeters; // latest destination wins
        ascentGas ??= leg.gas;
        ascentSetpoint ??= leg.setpointBar;
        hasAscent = true;
      }
      // 0-duration "stops" (degenerate; shouldn't appear post-planner) skipped.
    }

    // Trailing ascent = final surface ascent.
    if (hasAscent) {
      rows.add(ConsolidatedStopRow.ascent(
        targetDepthMeters: ascentTargetDepth,
        gas: ascentGas!,
        volumeLitres: ascentVolume,
        travelDuration: ascentDuration,
        setpointBar: ascentSetpoint,
      ));
    }
    return rows;
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  /// Diver-friendly mix name:
  ///   21/0 → "Air"
  ///   other 0% He → "EAN{O2}"
  ///   He > 0 → "Tx{O2}/{He}"
  static String mixLabel(DiveGasMix g) {
    if (g.heliumPercent > 0) return 'Tx${g.oxygenPercent}/${g.heliumPercent}';
    if (g.oxygenPercent == 21) return 'Air';
    return 'EAN${g.oxygenPercent}';
  }

  /// PPO2 in bar at [depthMeters] on [gas]. When [setpointBar] is set
  /// and > 0.1 the diver is on a CCR loop, so the displayed PPO2 IS
  /// the setpoint (clamped to ambient — at very shallow depths the loop
  /// can't actually hold a setpoint higher than ambient).
  static double ppo2At(DiveGasMix gas, double depthMeters,
      {double? setpointBar}) {
    final ambient = 1.013 + depthMeters / 10.0;
    if (setpointBar != null && setpointBar > 0.1) {
      return setpointBar > ambient ? ambient : setpointBar;
    }
    return (gas.oxygenPercent / 100.0) * ambient;
  }

  /// Gas density (g/L) at [depthMeters] on [gas]. On CCR (setpointBar
  /// set), the loop's O2 fraction is setpoint / ambient and the inert
  /// fractions are the diluent's inerts scaled to fill what's left.
  static double densityAt(DiveGasMix gas, double depthMeters,
      {double? setpointBar}) {
    final ambient = 1.013 + depthMeters / 10.0;
    double fO2 = gas.oxygenPercent / 100.0;
    double fHe = gas.heliumPercent / 100.0;
    if (setpointBar != null && setpointBar > 0.1) {
      final loopO2 = (setpointBar / ambient).clamp(0.0, 1.0);
      final dilHe = gas.heliumPercent / 100.0;
      final dilO2 = gas.oxygenPercent / 100.0;
      final dilN2 = 1.0 - dilO2 - dilHe;
      final dilInert = dilHe + dilN2;
      if (dilInert > 0 && loopO2 < 1.0) {
        final inert = 1.0 - loopO2;
        fO2 = loopO2;
        fHe = inert * (dilHe / dilInert);
      }
    }
    final atOneAtm = mixDensityAt1Atm(fO2, fHe);
    return atOneAtm * ambient;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _consolidate();
    final headerStyle = AppTypography.label.copyWith(
      color: scheme.outlineVariant,
      fontSize: 10,
    );
    final cellStyle = AppTypography.readoutSm.copyWith(
      color: AppColors.wreck.textPrimary,
    );

    // Cumulative runtime starts at the dive time already elapsed before
    // the bailout trigger so the column reads as TOTAL dive runtime.
    var runtime = startingRuntime;

    // ICD severity per row, by comparing each row's gas to the one
    // breathed on the previous row. The row where a risky switch
    // *starts* (i.e. first row on the new gas) gets the tint.
    final rowSeverities = <IcdSeverity>[];
    DiveGasMix? prevGas;
    for (final row in rows) {
      final severity = (prevGas != null && row.gas != prevGas)
          ? icdSeverityBetween(prevGas, row.gas)
          : IcdSeverity.none;
      rowSeverities.add(severity);
      prevGas = row.gas;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text('DEPTH', style: headerStyle)),
              Expanded(flex: 2, child: Text('T', style: headerStyle)),
              Expanded(flex: 2, child: Text('RT', style: headerStyle)),
              Expanded(flex: 2, child: Text('GAS', style: headerStyle)),
              Expanded(flex: 2, child: Text('PPO2', style: headerStyle)),
              Expanded(flex: 2, child: Text('ρ g/L', style: headerStyle)),
              Expanded(flex: 2, child: Text('VOL (L)', style: headerStyle)),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFF2A3A45)), // surfaceBezel
        for (var i = 0; i < rows.length; i++) ...[
          Builder(builder: (context) {
            final row = rows[i];
            runtime += row.stopDuration;
            final depthLabel = row.isStop
                ? '${row.depthMeters.toStringAsFixed(0)} m'
                : (row.depthMeters == 0
                    ? '→ surface'
                    : '→ ${row.depthMeters.toStringAsFixed(0)} m');
            // "—" in the STOP column for ascent rows tells the diver this
            // line is a transition, not a hold.
            final stopLabel =
                row.isStop ? _fmtMinutes(row.stopDuration) : '—';
            final runtimeLabel = _fmtMinutes(runtime);
            final volLabel = row.volumeLitres.round().toString();
            final gasLabel = mixLabel(row.gas);
            // PPO2 + density evaluated at the row's effective depth — for
            // stops that's the stop depth, for ascent rows the destination.
            // Worst-case-on-leg lives on the deeper side; using the row
            // depth slightly under-reads ascent rows but keeps the table
            // single-valued per cell.
            final ppo2Label = ppo2At(row.gas, row.depthMeters,
                    setpointBar: row.setpointBar)
                .toStringAsFixed(2);
            final rhoLabel = densityAt(row.gas, row.depthMeters,
                    setpointBar: row.setpointBar)
                .toStringAsFixed(1);

            final severity = rowSeverities[i];
            final tint = switch (severity) {
              IcdSeverity.severe =>
                icdRedAccent.withValues(alpha: 0.16),
              IcdSeverity.marginal =>
                icdAmberAccent.withValues(alpha: 0.14),
              IcdSeverity.none => Colors.transparent,
            };

            return Container(
              color: tint,
              padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text(depthLabel, style: cellStyle)),
                  Expanded(flex: 2, child: Text(stopLabel, style: cellStyle)),
                  Expanded(flex: 2, child: Text(runtimeLabel, style: cellStyle)),
                  Expanded(flex: 2, child: Text(gasLabel, style: cellStyle)),
                  Expanded(flex: 2, child: Text(ppo2Label, style: cellStyle)),
                  Expanded(flex: 2, child: Text(rhoLabel, style: cellStyle)),
                  Expanded(flex: 2, child: Text(volLabel, style: cellStyle)),
                ],
              ),
            );
          }),
          const Divider(
            height: 1,
            color: Color(0xFF1A2832), // chartGrid
          ),
        ],
      ],
    );
  }
}

/// One displayed row in the bailout-plan table. Either a stop hold or an
/// ascent transition. For ascent rows [stopDuration] is the travel duration
/// and [depthMeters] is the *destination* depth (0 means surface).
class ConsolidatedStopRow {
  const ConsolidatedStopRow.stop({
    required this.depthMeters,
    required this.stopDuration,
    required this.gas,
    required this.volumeLitres,
    this.setpointBar,
  }) : isStop = true;

  const ConsolidatedStopRow.ascent({
    required double targetDepthMeters,
    required this.gas,
    required this.volumeLitres,
    required Duration travelDuration,
    this.setpointBar,
  })  : isStop = false,
        depthMeters = targetDepthMeters,
        stopDuration = travelDuration;

  final bool isStop;
  final double depthMeters;

  /// Stop hold for stop rows; ascent travel duration for ascent rows.
  /// Always counts toward runtime; the table renders "—" in the STOP TIME
  /// column for ascent rows so the diver can tell them apart at a glance.
  final Duration stopDuration;
  final DiveGasMix gas;
  final double volumeLitres;

  /// CCR loop setpoint (bar) for this leg. Null / ≤ 0.1 = open circuit;
  /// the renderer falls back to fO2 × ambient for the PPO2 column.
  final double? setpointBar;
}

// ── Private file-level helpers ───────────────────────────────────────────────

/// Whole-minute, rounded UP so a 1:01 hold doesn't read as "1". Returns
/// just the integer — the column headers carry the unit.
String _fmtMinutes(Duration d) {
  final m = (d.inSeconds + 59) ~/ 60;
  return '$m';
}
