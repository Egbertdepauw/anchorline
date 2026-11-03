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

import '../../analysis/bailout/bailout_result.dart';
import '../../analysis/bailout/icd.dart'
    show IcdRisk, IcdSeverity, detectIcdRisks;
import '../../analysis/bailout/team_bailout.dart'
    show TeamCarry, TeamGasStage;
import 'package:subsurface_core/data/models/dive.dart' show DiveGasMix;
import '../components/section_header.dart';
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';
import 'stop_ladder_table.dart';

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

  /// Team-bailout per-diver carry suggestion. Empty when the dive has no
  /// buddies (team size 1) — the solo verdict already IS the carry.
  final List<TeamCarry> teamCarry;

  const BailoutSection({
    super.key,
    required this.result,
    required this.triggerDepthMeters,
    required this.sacBottom,
    required this.sacDeco,
    required this.isGueConfig,
    this.bottomTimeBeforeTrigger = Duration.zero,
    this.teamCarry = const [],
  });

  // ── Colour helpers ──────────────────────────────────────────────────

  Color get _scenarioAccent => result?.scenario == BailoutScenario.tanksDefined
      ? SafetyColors.info
      : SafetyColors.warning;

  Color get _verdictAccent {
    return switch (result?.verdict) {
      BailoutVerdict.sufficient => SafetyColors.success,
      BailoutVerdict.partialShortfall => SafetyColors.warning,
      BailoutVerdict.insufficient => SafetyColors.danger,
      null => SafetyColors.warning,
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
    // Sum tanks across all gases (a single gas that overflows one tank
    // contributes multiple stages — the user carries N cylinders of
    // the same gas to cover the required volume).
    return result!.perGas.values
        .where((u) => u.recommendedTank != null)
        .fold<int>(0, (sum, u) => sum + u.recommendedTank!.count);
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
          // ── Scenario banner (always above any tabs) ─────────────────
          _Banner(
            accent: _scenarioAccent,
            child: Text(
              _scenarioBanner(),
              style: AppTypography.caption.copyWith(
                color: context.palette.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: Spacing.sm),

          if (teamCarry.isEmpty)
            _buildSoloContent(context, r, scheme)
          else
            _buildTabbedContent(context, r, scheme),
        ],
      ],
    );
  }

  // ── Tabbed wrapper ─────────────────────────────────────────────────────

  Widget _buildTabbedContent(
      BuildContext context, BailoutResult r, ColorScheme scheme) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TabBar(
            tabs: [Tab(text: 'Solo'), Tab(text: 'Team')],
            isScrollable: false,
          ),
          const SizedBox(height: Spacing.sm),
          // No fixed TabBarView height — instead select via the inherited
          // controller so each tab body sizes to its content. The bailout
          // stop table can be ~25 rows on a deep dive; a Team view is only
          // a handful of lines. Letting each tab size to its content keeps
          // the parent ListView's scroll height honest.
          Builder(builder: (context) {
            final controller = DefaultTabController.of(context);
            return AnimatedBuilder(
              animation: controller,
              builder: (_, _) {
                return controller.index == 0
                    ? _buildSoloContent(context, r, scheme)
                    : _buildTeamContent(context, r);
              },
            );
          }),
        ],
      ),
    );
  }

  // ── Solo content (the worst-case ascent + table + verdict) ────────────

  Widget _buildSoloContent(
      BuildContext context, BailoutResult r, ColorScheme scheme) {
    final icdRisks = detectIcdRisks(r.stops);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary row
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
        // Per-stop table
        if (r.stops.isNotEmpty) ...[
          const SizedBox(height: Spacing.md),
          StopLadderTable(
            stops: r.stops,
            scheme: scheme,
            startingRuntime: bottomTimeBeforeTrigger,
          ),
        ],
        // ICD warning (above verdict so it's seen before the green/amber
        // verdict colour conditions the diver's read of the plan).
        if (icdRisks.isNotEmpty) ...[
          const SizedBox(height: Spacing.sm),
          _IcdBanner(risks: icdRisks),
        ],
        // Verdict banner
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
                    color: context.palette.textPrimary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Team content (per-diver carry) ────────────────────────────────────

  Widget _buildTeamContent(BuildContext context, BailoutResult r) {
    final icdRisks = detectIcdRisks(r.stops);
    final hasSevere = icdRisks.any((x) => x.severity == IcdSeverity.severe);

    // Suggest the next missing standard intermediate when there's still
    // a severe switch — TX 21/35 first (deepest standard intermediate),
    // then TX 35/25 if TX 21/35 is already on the team.
    final teamGases = <DiveGasMix>{};
    for (final d in teamCarry) {
      for (final s in d.stages) {
        teamGases.add(s.gas);
      }
    }
    bool hasMix(int o2, int he) =>
        teamGases.any((g) => g.oxygenPercent == o2 && g.heliumPercent == he);
    String? suggestion;
    if (hasSevere) {
      if (!hasMix(21, 35)) {
        suggestion = 'TX 21/35 (57 m switch depth)';
      } else if (!hasMix(35, 25)) {
        suggestion = 'TX 35/25 (36 m switch depth)';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Banner(
          accent: SafetyColors.info,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Team of ${teamCarry.length} — suggested per-diver carry',
                style: AppTypography.caption.copyWith(
                  color: context.palette.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              for (final diver in teamCarry) ...[
                Text(
                  'Diver ${diver.diverIndex}',
                  style: AppTypography.caption.copyWith(
                    color: context.palette.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                for (final s in diver.stages)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      _formatStage(s),
                      style: AppTypography.caption.copyWith(
                        color: context.palette.textPrimary,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
              ],
            ],
          ),
        ),
        if (icdRisks.isNotEmpty) ...[
          const SizedBox(height: Spacing.sm),
          _IcdBanner(risks: icdRisks),
        ],
        if (suggestion != null) ...[
          const SizedBox(height: Spacing.sm),
          _Banner(
            accent: SafetyColors.warning,
            child: Text(
              'Suggestion: add $suggestion to one diver\'s carry to '
              'shrink the helium gradient at the bottom-mix switch.',
              style: AppTypography.caption.copyWith(
                color: context.palette.textPrimary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// "  TMX 9/68 — 900 L → AL40 @ 158 bar"
  static String _formatStage(TeamGasStage stage) {
    final mix = StopLadderTable.mixLabel(stage.gas);
    final vol = stage.perStageVolumeL.round();
    final tank = stage.tank;
    if (tank == null) return '  $mix — $vol L';
    final count = tank.count > 1 ? '${tank.count}× ' : '';
    return '  $mix — $vol L → $count${tank.tank.name} @ '
        '${tank.minFillPressureBar} bar';
  }
}

/// ICD risk banner — amber for marginal, red for severe. Lists each flagged
/// switch with its from/to gases, switch depth, and the rule it broke.
class _IcdBanner extends StatelessWidget {
  const _IcdBanner({required this.risks});

  final List<IcdRisk> risks;

  @override
  Widget build(BuildContext context) {
    final anySevere = risks.any((r) => r.severity == IcdSeverity.severe);
    final accent = anySevere
        ? SafetyColors.danger
        : SafetyColors.warning;
    final header = anySevere
        ? 'ICD risk — severe gas switch(es) detected'
        : 'ICD risk — switch breaks the 5:1 rule';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: Spacing.xs),
      padding: const EdgeInsets.all(Spacing.sm + 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: Radii.cardBr,
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            header,
            style: AppTypography.caption.copyWith(
              color: context.palette.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          for (final risk in risks)
            Text(
              _formatRisk(risk),
              style: AppTypography.caption.copyWith(
                color: context.palette.textSecondary,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'Doolette/Mitchell: ΔO₂ should not exceed |ΔHe|/5. Inserting an '
            'intermediate trimix reduces the helium gradient at each switch.',
            style: AppTypography.caption.copyWith(
              color: context.palette.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatRisk(IcdRisk r) {
    final from = StopLadderTable.mixLabel(r.fromGas);
    final to = StopLadderTable.mixLabel(r.toGas);
    final depth = r.switchDepthMeters.toStringAsFixed(0);
    final severity = r.severity == IcdSeverity.severe ? 'severe' : 'marginal';
    final dO2 = r.deltaO2 >= 0 ? '+${r.deltaO2}' : '${r.deltaO2}';
    return '  • $from → $to at $depth m '
        '(ΔO₂ $dO2 / ΔHe ${r.deltaHe} — $severity)';
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
        color: context.palette.surfaceRaised,
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
              color: context.palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

