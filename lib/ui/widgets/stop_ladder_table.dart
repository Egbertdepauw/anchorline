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
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';

/// Per-stop ascent table. Adjacent minute-steps with the same gas and
/// same depth are consolidated into single rows for readability.
class StopLadderTable extends StatelessWidget {
  const StopLadderTable({
    super.key,
    required this.stops,
    required this.scheme,
    this.startingRuntime = Duration.zero,
    this.icdRedAccent = SafetyColors.danger,
    this.icdAmberAccent = SafetyColors.warning,
    this.gasSwitchAccent = SafetyColors.info,
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

  /// Colour used for benign gas-switch tints — rows where the diver
  /// changed gas but the switch carries no ICD penalty. A subtle blue
  /// flag so the eye picks the switch out of the ladder at a glance.
  final Color gasSwitchAccent;

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

  /// Equivalent Narcotic Depth (m) at [depthMeters] on [gas]. Treats O2
  /// as non-narcotic (the conservative "countsOxygen=false" convention
  /// most tech divers use day-to-day). On CCR (setpointBar set), the
  /// loop's helium fraction is the diluent's helium scaled into the
  /// inert headroom left after the setpoint claim — at shallow depths
  /// where the loop runs O2-rich, fHe drops and END creeps toward depth.
  static double endAt(DiveGasMix gas, double depthMeters,
      {double? setpointBar}) {
    double fHe = gas.heliumPercent / 100.0;
    if (setpointBar != null && setpointBar > 0.1) {
      final ambient = 1.013 + depthMeters / 10.0;
      final loopO2 = (setpointBar / ambient).clamp(0.0, 1.0);
      final dilO2 = gas.oxygenPercent / 100.0;
      final dilHe = gas.heliumPercent / 100.0;
      final dilN2 = 1.0 - dilO2 - dilHe;
      final dilInert = dilHe + dilN2;
      if (dilInert > 0 && loopO2 < 1.0) {
        final inert = 1.0 - loopO2;
        fHe = inert * (dilHe / dilInert);
      }
    }
    // END = (depth + 10) × (1 - fHe) − 10. Negative results clamp to 0 —
    // a high-He mix at shallow depth has no narcotic load.
    final end = (depthMeters + 10) * (1.0 - fHe) - 10;
    return end < 0 ? 0 : end;
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

  /// Single-line table cell — never wraps, fades on overflow. Used for
  /// every header + body cell so the row stays at one line on the
  /// smaller phones too. Worst-case "Tx12/65" should still fit with
  /// the flex weights below; this is a safety net for narrow screens.
  /// [textAlign] is propagated so numeric columns can right-align
  /// (their values vary in width and read better that way).
  static Widget _cellText(
    String text,
    TextStyle style, {
    TextAlign? textAlign,
  }) =>
      Text(
        text,
        style: style,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        textAlign: textAlign,
      );

  @override
  Widget build(BuildContext context) {
    final rows = _consolidate();
    final headerStyle = AppTypography.label.copyWith(
      color: scheme.outlineVariant,
      fontSize: 10,
    );
    final cellStyle = AppTypography.readoutSm.copyWith(
      color: context.palette.textPrimary,
    );

    // Cumulative runtime starts at the dive time already elapsed before
    // the bailout trigger so the column reads as TOTAL dive runtime.
    var runtime = startingRuntime;

    // ICD severity + benign-gas-switch flag per row. ICD takes precedence
    // — a marginal/severe switch already implies a gas change, no need
    // to double-tint. A "switch" is the first row on a different gas
    // than the previous row.
    final rowSeverities = <IcdSeverity>[];
    final rowIsBenignSwitch = <bool>[];
    DiveGasMix? prevGas;
    for (final row in rows) {
      final isSwitch = prevGas != null && row.gas != prevGas;
      final severity = isSwitch
          ? icdSeverityBetween(prevGas, row.gas)
          : IcdSeverity.none;
      rowSeverities.add(severity);
      rowIsBenignSwitch.add(isSwitch && severity == IcdSeverity.none);
      prevGas = row.gas;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header — DEPTH | T | RT | GAS | PPO2 | END | ρ | VOL.
        // END sits between PPO2 and density so the narcosis / density
        // sanity check reads left-to-right (oxy → narcotic → physical).
        // Flex weights tuned so "Tx12/65" (worst-case 7-char gas label)
        // fits without wrapping on iPhone 16 Pro and similar widths.
        // T and RT only ever show 1-3 chars so they take the minimum
        // share; GAS gets double because that's the longest cell.
        // Every cell — header and body — is centered. Right-aligning
        // numeric columns visually smashed adjacent narrow columns
        // together (T's "45" touching RT's "49" with only a 6 pt gap);
        // centering puts each value in the middle of its own cell, so
        // there's natural breathing room on both sides.
        // Flex: T and RT are bumped back to 2 so the column has room
        // for 2-digit values + centering padding without crowding.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
          child: Row(
            children: [
              Expanded(flex: 3, child: _cellText('DEPTH', headerStyle, textAlign: TextAlign.center)),
              Expanded(flex: 2, child: _cellText('T', headerStyle, textAlign: TextAlign.center)),
              Expanded(flex: 2, child: _cellText('RT', headerStyle, textAlign: TextAlign.center)),
              Expanded(flex: 4, child: _cellText('GAS', headerStyle, textAlign: TextAlign.center)),
              Expanded(flex: 2, child: _cellText('PPO2', headerStyle, textAlign: TextAlign.center)),
              Expanded(flex: 2, child: _cellText('END', headerStyle, textAlign: TextAlign.center)),
              Expanded(flex: 2, child: _cellText('ρ g/L', headerStyle, textAlign: TextAlign.center)),
              Expanded(flex: 1, child: _cellText('VOL', headerStyle, textAlign: TextAlign.center)),
            ],
          ),
        ),
        Divider(height: 1, color: context.palette.surfaceBezel),
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
            // PPO2 + END + density evaluated at the row's effective depth —
            // for stops that's the stop depth, for ascent rows the destination.
            // Worst-case-on-leg lives on the deeper side; using the row
            // depth slightly under-reads ascent rows but keeps the table
            // single-valued per cell.
            final ppo2Value =
                ppo2At(row.gas, row.depthMeters, setpointBar: row.setpointBar);
            final endLabel =
                '${endAt(row.gas, row.depthMeters, setpointBar: row.setpointBar).round()} m';
            final rhoLabel = densityAt(row.gas, row.depthMeters,
                    setpointBar: row.setpointBar)
                .toStringAsFixed(1);
            // Dedupe GAS + PPO2 across consecutive rows so the diver
            // sees "what changes" rather than scanning a column of
            // identical Tx12/65 / 1.30 rows. The first row always
            // shows real values; "—" elsewhere when unchanged.
            final prev = i > 0 ? rows[i - 1] : null;
            final gasChanged = prev == null || row.gas != prev.gas;
            final gasLabel = gasChanged ? mixLabel(row.gas) : '—';
            final prevPpo2 = prev == null
                ? null
                : ppo2At(prev.gas, prev.depthMeters,
                    setpointBar: prev.setpointBar);
            final ppo2Changed =
                prevPpo2 == null || (ppo2Value - prevPpo2).abs() > 0.005;
            final ppo2Label =
                ppo2Changed ? ppo2Value.toStringAsFixed(2) : '—';

            final severity = rowSeverities[i];
            final isBenignSwitch = rowIsBenignSwitch[i];
            final tint = switch (severity) {
              IcdSeverity.severe =>
                icdRedAccent.withValues(alpha: 0.16),
              IcdSeverity.marginal =>
                icdAmberAccent.withValues(alpha: 0.14),
              IcdSeverity.none => isBenignSwitch
                  ? gasSwitchAccent.withValues(alpha: 0.12)
                  : Colors.transparent,
            };

            return Container(
              color: tint,
              padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
              child: Row(
                children: [
                  Expanded(flex: 3, child: _cellText(depthLabel, cellStyle, textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: _cellText(stopLabel, cellStyle, textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: _cellText(runtimeLabel, cellStyle, textAlign: TextAlign.center)),
                  Expanded(flex: 4, child: _cellText(gasLabel, cellStyle, textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: _cellText(ppo2Label, cellStyle, textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: _cellText(endLabel, cellStyle, textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: _cellText(rhoLabel, cellStyle, textAlign: TextAlign.center)),
                  Expanded(flex: 1, child: _cellText(volLabel, cellStyle, textAlign: TextAlign.center)),
                ],
              ),
            );
          }),
          Divider(
            height: 1,
            color: context.palette.chartGrid,
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
