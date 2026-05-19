/// BailoutSection — renders the output of the bailout planner.
///
/// Takes a [BailoutResult] and renders:
///   1. Section header
///   2. Scenario banner (blue for A / user tanks, amber for B / GUE standards)
///   3. 3-tile summary row (total time · total volume · available or stages)
///   4. Per-stop ascent table
///   5. Verdict banner (green / amber / red by sufficiency)
library;

import 'package:flutter/material.dart';

import '../../analysis/bailout/ascent_simulator.dart' show AscentStop;
import '../../analysis/bailout/bailout_result.dart';
import '../../analysis/gas_density.dart' show mixDensityAt1Atm;
import '../../data/models/dive.dart' show DiveGasMix;
import '../components/section_header.dart';
import '../theme/tokens.dart';

class BailoutSection extends StatelessWidget {
  final BailoutResult? result; // null while loading
  final double triggerDepthMeters;
  final int sacBottom;
  final int sacDeco;
  final bool isGueConfig;

  /// Dive runtime accumulated before the bailout trigger (i.e. depth/time
  /// from descent + bottom phase up to the deepest sample). The stop table
  /// adds bailout-leg durations on top of this so the RUNTIME column shows
  /// total elapsed dive time, not just elapsed-since-trigger.
  final Duration bottomTimeBeforeTrigger;

  const BailoutSection({
    super.key,
    required this.result,
    required this.triggerDepthMeters,
    required this.sacBottom,
    required this.sacDeco,
    required this.isGueConfig,
    this.bottomTimeBeforeTrigger = Duration.zero,
  });

  // ── Colour helpers ──────────────────────────────────────────────────

  static const _blue = Color(0xFF60A5FA); // statusInfo
  static const _amber = Color(0xFFF39C12); // statusWarning
  static const _green = Color(0xFF4ADE80); // statusSuccess
  static const _red = Color(0xFFE74C3C); // statusDanger

  Color get _scenarioAccent =>
      result?.scenario == BailoutScenario.tanksDefined ? _blue : _amber;

  Color get _verdictAccent {
    return switch (result?.verdict) {
      BailoutVerdict.sufficient => _green,
      BailoutVerdict.partialShortfall => _amber,
      BailoutVerdict.insufficient => _red,
      null => _amber,
    };
  }

  // ── Scenario banner copy ────────────────────────────────────────────

  String _scenarioBanner() {
    final depth = triggerDepthMeters.toStringAsFixed(0);
    if (result?.scenario == BailoutScenario.gueStandards) {
      return 'GUE standards — no user bailout tanks defined. '
          'Worst-case bailout from $depth m · bottom SAC $sacBottom L/min · '
          'deco SAC $sacDeco L/min.';
    }
    return 'User-defined bailout tanks. '
        'Worst-case bailout from $depth m · bottom SAC $sacBottom L/min · '
        'deco SAC $sacDeco L/min.';
  }

  // ── Volume accounting ───────────────────────────────────────────────

  double _totalVolumeL() {
    if (result == null) return 0;
    return result!.perGas.values.fold(0.0, (sum, u) => sum + u.requiredL);
  }

  double? _totalAvailableL() {
    if (result == null) return null;
    if (result!.scenario != BailoutScenario.tanksDefined) return null;
    double total = 0;
    for (final u in result!.perGas.values) {
      if (u.availableL == null) return null;
      total += u.availableL!;
    }
    return total;
  }

  int? _stagesNeeded() {
    if (result == null) return null;
    if (result!.scenario != BailoutScenario.gueStandards) return null;
    return result!.perGas.values
        .where((u) => u.recommendedTank != null)
        .length;
  }

  // ── Summary tile label/value for the third column ──────────────────

  (String, String) _thirdTile() {
    if (result?.scenario == BailoutScenario.gueStandards) {
      final n = _stagesNeeded();
      return ('Stages needed', n == null ? '—' : '$n');
    }
    final avail = _totalAvailableL();
    return ('Available', avail == null ? '—' : '${avail.round()} L');
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = result;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Bailout'),
        const Text(
          'Bailout — worst case from max depth',
          style: AppTypography.caption,
        ),
        const SizedBox(height: Spacing.xs),
        if (r == null) ...[
          const SizedBox(height: Spacing.lg),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: Spacing.lg),
        ] else ...[
          // ── Scenario banner ─────────────────────────────────────────
          _Banner(
            accent: _scenarioAccent,
            child: Text(
              _scenarioBanner(),
              style: AppTypography.caption.copyWith(
                color: AppColors.wreck.textSecondary,
              ),
            ),
          ),

          // ── Summary row ─────────────────────────────────────────────
          const SizedBox(height: Spacing.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _SummaryTile(
                    label: 'Total time',
                    value: '${r.totalTime.inMinutes} min',
                    scheme: scheme,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: _SummaryTile(
                    label: 'Total vol',
                    value: '${_totalVolumeL().round()} L',
                    scheme: scheme,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: _SummaryTile(
                    label: _thirdTile().$1,
                    value: _thirdTile().$2,
                    scheme: scheme,
                  ),
                ),
              ],
            ),
          ),

          // ── Per-stop table ───────────────────────────────────────────
          if (r.stops.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            _StopTable(
              stops: r.stops,
              scheme: scheme,
              startingRuntime: bottomTimeBeforeTrigger,
            ),
          ],

          // ── Verdict banner ───────────────────────────────────────────
          const SizedBox(height: Spacing.sm),
          _Banner(
            accent: _verdictAccent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in r.verdictDetails)
                  Text(
                    line,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.wreck.textPrimary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ── Private sub-widgets ─────────────────────────────────────────────────────

/// Left-accented banner used for scenario + verdict strips.
class _Banner extends StatelessWidget {
  const _Banner({required this.accent, required this.child});

  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: Spacing.xs),
      padding: const EdgeInsets.all(Spacing.sm + 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: Radii.cardBr,
        border: Border(
          left: BorderSide(color: accent, width: 3),
        ),
      ),
      child: child,
    );
  }
}

/// Single labelled stat tile used inside the 3-column summary row.
class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.scheme,
  });

  final String label;
  final String value;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.wreck.surfaceRaised,
        borderRadius: Radii.cardBr,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTypography.label.copyWith(
              color: scheme.outlineVariant,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTypography.readoutSm.copyWith(
              color: AppColors.wreck.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Per-stop ascent table. Adjacent minute-steps with the same gas and
/// same depth are consolidated into single rows for readability.
class _StopTable extends StatelessWidget {
  const _StopTable({
    required this.stops,
    required this.scheme,
    this.startingRuntime = Duration.zero,
  });

  final List<AscentStop> stops;
  final ColorScheme scheme;

  /// Dive runtime accumulated before the bailout trigger. The RUNTIME
  /// column counts up from here.
  final Duration startingRuntime;

  // ── Row consolidation ────────────────────────────────────────────────
  //
  // The planner emits one leg per minute (1m ascents + 3m stop holds). The
  // diver wants a stop-oriented view a la MultiDeco: one row per stop, plus
  // a transit row whenever a meaningful ascent (trigger→first-stop and
  // final stop→surface) precedes/follows a stop. Intermediate inter-stop
  // 3m ascents fold into the *following* stop's volume since they're tiny
  // and not separately interesting.

  List<_ConsolidatedRow> _consolidate() {
    final rows = <_ConsolidatedRow>[];
    Duration ascentDuration = Duration.zero;
    double ascentVolume = 0.0;
    double ascentTargetDepth = 0;
    DiveGasMix? ascentGas;
    var hasAscent = false;
    var seenAnyStop = false;

    for (final leg in stops) {
      final isRealStop = leg.isStop && leg.duration > Duration.zero;
      if (isRealStop) {
        // Only emit the trigger→first-stop transit as its own row. Inter-
        // stop ascents fold into the stop they precede so the table reads
        // as a clean stop ladder.
        if (hasAscent && !seenAnyStop) {
          rows.add(_ConsolidatedRow.ascent(
            targetDepthMeters: ascentTargetDepth,
            gas: ascentGas!,
            volumeLitres: ascentVolume,
            travelDuration: ascentDuration,
          ));
          ascentDuration = Duration.zero;
          ascentVolume = 0.0;
          hasAscent = false;
          ascentGas = null;
        }
        rows.add(_ConsolidatedRow.stop(
          depthMeters: leg.depthStartMeters,
          stopDuration: leg.duration,
          gas: leg.gas,
          // Fold pending inter-stop ascent volume into this stop so
          // nothing falls off the totals.
          volumeLitres: leg.volumeLitresConsumed + ascentVolume,
        ));
        // Inter-stop ascent time gets attributed to the stop it preceded.
        // It's already in totalTime via the planner's sum.
        ascentDuration = Duration.zero;
        ascentVolume = 0.0;
        hasAscent = false;
        ascentGas = null;
        seenAnyStop = true;
      } else if (!leg.isStop) {
        // Ascent leg. Track destination + accumulate. If the gas
        // changes mid-ascent (e.g. 67 m → 22 m on bottom mix then 22 m →
        // 15 m on EAN 50), emit the accumulated row first so each
        // displayed gas matches the leg it was actually breathed on.
        if (hasAscent && !seenAnyStop && ascentGas != leg.gas) {
          rows.add(_ConsolidatedRow.ascent(
            targetDepthMeters: ascentTargetDepth,
            gas: ascentGas!,
            volumeLitres: ascentVolume,
            travelDuration: ascentDuration,
          ));
          ascentDuration = Duration.zero;
          ascentVolume = 0.0;
          ascentGas = null;
        }
        ascentDuration += leg.duration;
        ascentVolume += leg.volumeLitresConsumed;
        ascentTargetDepth = leg.depthEndMeters; // latest destination wins
        ascentGas ??= leg.gas;
        hasAscent = true;
      }
      // 0-duration "stops" (degenerate; shouldn't appear post-planner) skipped.
    }

    // Trailing ascent = final surface ascent.
    if (hasAscent) {
      rows.add(_ConsolidatedRow.ascent(
        targetDepthMeters: ascentTargetDepth,
        gas: ascentGas!,
        volumeLitres: ascentVolume,
        travelDuration: ascentDuration,
      ));
    }
    return rows;
  }

  // ── Runtime accumulation ─────────────────────────────────────────────

  /// Diver-friendly mix name:
  ///   21/0 -> "Air"
  ///   other 0% He -> "EAN{O2}"
  ///   He > 0 -> "Tx{O2}/{He}"
  static String _mixLabel(DiveGasMix g) {
    if (g.heliumPercent > 0) {
      return 'Tx${g.oxygenPercent}/${g.heliumPercent}';
    }
    if (g.oxygenPercent == 21) return 'Air';
    return 'EAN${g.oxygenPercent}';
  }

  /// Whole-minute, rounded UP so a 1:01 hold doesn't read as "1". Returns
  /// just the integer — the column headers carry the unit.
  static String _fmtMinutes(Duration d) {
    final m = (d.inSeconds + 59) ~/ 60;
    return '$m';
  }

  /// PPO2 in bar at [depthMeters] on [gas]. 1.013 bar atmospheric + 0.1
  /// bar / m water column. Returned to 2 decimals.
  static double ppo2At(DiveGasMix gas, double depthMeters) {
    final ambient = 1.013 + depthMeters / 10.0;
    return (gas.oxygenPercent / 100.0) * ambient;
  }

  /// Gas density (g/L) at [depthMeters] on [gas]: 1-ATA density × ambient.
  static double densityAt(DiveGasMix gas, double depthMeters) {
    final ambient = 1.013 + depthMeters / 10.0;
    final atOneAtm = mixDensityAt1Atm(
      gas.oxygenPercent / 100.0,
      gas.heliumPercent / 100.0,
    );
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
        for (final row in rows) ...[
          Builder(builder: (context) {
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
            final gasLabel = _mixLabel(row.gas);
            // PPO2 + density evaluated at the row's effective depth — for
            // stops that's the stop depth, for ascent rows the destination.
            // Worst-case-on-leg lives on the deeper side; using the row
            // depth slightly under-reads ascent rows but keeps the table
            // single-valued per cell.
            final ppo2Label = ppo2At(row.gas, row.depthMeters).toStringAsFixed(2);
            final rhoLabel =
                densityAt(row.gas, row.depthMeters).toStringAsFixed(1);

            return Padding(
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
/// ascent transition. For ascent rows [stopDuration] is null and
/// [depthMeters] is the *destination* depth (0 means surface).
class _ConsolidatedRow {
  const _ConsolidatedRow.stop({
    required this.depthMeters,
    required this.stopDuration,
    required this.gas,
    required this.volumeLitres,
  }) : isStop = true;

  const _ConsolidatedRow.ascent({
    required double targetDepthMeters,
    required this.gas,
    required this.volumeLitres,
    required Duration travelDuration,
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
}
