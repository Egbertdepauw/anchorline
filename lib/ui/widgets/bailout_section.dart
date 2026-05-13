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
import '../../data/models/dive.dart' show DiveGasMix;
import '../components/section_header.dart';
import '../theme/tokens.dart';

class BailoutSection extends StatelessWidget {
  final BailoutResult? result; // null while loading
  final double triggerDepthMeters;
  final int sacBottom;
  final int sacDeco;
  final bool isGueConfig;

  const BailoutSection({
    super.key,
    required this.result,
    required this.triggerDepthMeters,
    required this.sacBottom,
    required this.sacDeco,
    required this.isGueConfig,
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
            _StopTable(stops: r.stops, scheme: scheme),
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
  const _StopTable({required this.stops, required this.scheme});

  final List<AscentStop> stops;
  final ColorScheme scheme;

  // ── Row consolidation ────────────────────────────────────────────────

  List<_ConsolidatedRow> _consolidate() {
    final rows = <_ConsolidatedRow>[];
    for (final stop in stops) {
      if (rows.isNotEmpty) {
        final last = rows.last;
        final sameGas = last.gas == stop.gas;
        final sameDepthRange = last.depthStartMeters == stop.depthStartMeters &&
            last.depthEndMeters == stop.depthEndMeters;
        if (sameGas && sameDepthRange) {
          rows.last = _ConsolidatedRow(
            depthStartMeters: last.depthStartMeters,
            depthEndMeters: last.depthEndMeters,
            duration: last.duration + stop.duration,
            gas: last.gas,
            volumeLitres: last.volumeLitres + stop.volumeLitresConsumed,
          );
          continue;
        }
      }
      rows.add(_ConsolidatedRow(
        depthStartMeters: stop.depthStartMeters,
        depthEndMeters: stop.depthEndMeters,
        duration: stop.duration,
        gas: stop.gas,
        volumeLitres: stop.volumeLitresConsumed,
      ));
    }
    return rows;
  }

  // ── Runtime accumulation ─────────────────────────────────────────────

  static String _mixLabel(DiveGasMix g) {
    final he = g.heliumPercent > 0 ? '/${g.heliumPercent}' : '';
    return '${g.oxygenPercent}$he';
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

    // Track cumulative runtime
    var runtime = Duration.zero;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text('DEPTH (m)', style: headerStyle)),
              Expanded(flex: 2, child: Text('TIME', style: headerStyle)),
              Expanded(flex: 2, child: Text('GAS', style: headerStyle)),
              Expanded(flex: 2, child: Text('RUNTIME', style: headerStyle)),
              Expanded(flex: 2, child: Text('VOL (L)', style: headerStyle)),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFF2A3A45)), // surfaceBezel
        for (final row in rows) ...[
          Builder(builder: (context) {
            runtime += row.duration;
            final depthLabel = row.depthStartMeters == row.depthEndMeters
                ? '${row.depthStartMeters.toStringAsFixed(0)} m'
                : '${row.depthStartMeters.toStringAsFixed(0)}→'
                    '${row.depthEndMeters.toStringAsFixed(0)} m';
            final timeLabel = '${row.duration.inMinutes} min';
            final runtimeLabel = '${runtime.inMinutes} min';
            final volLabel = row.volumeLitres.round().toString();
            final gasLabel = _mixLabel(row.gas);

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text(depthLabel, style: cellStyle)),
                  Expanded(flex: 2, child: Text(timeLabel, style: cellStyle)),
                  Expanded(flex: 2, child: Text(gasLabel, style: cellStyle)),
                  Expanded(flex: 2, child: Text(runtimeLabel, style: cellStyle)),
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

/// A consolidated ascent stop row — adjacent same-gas same-depth stops merged.
class _ConsolidatedRow {
  const _ConsolidatedRow({
    required this.depthStartMeters,
    required this.depthEndMeters,
    required this.duration,
    required this.gas,
    required this.volumeLitres,
  });

  final double depthStartMeters;
  final double depthEndMeters;
  final Duration duration;
  final DiveGasMix gas;
  final double volumeLitres;
}
