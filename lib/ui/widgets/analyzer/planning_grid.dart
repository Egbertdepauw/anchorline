/// The Analyse tab's planning section: MOD per configured ppO₂, END,
/// density, minimum depth, gas temperature and ambient pressure as a
/// 4-column grid of small stat tiles, with the footnote behind an ⓘ on a
/// phone and shown on wide.
library;

import 'package:flutter/material.dart';

import '../../../analysis/end.dart';
import '../../../analysis/gas_density.dart';
import '../../../analysis/mix_match.dart';
import '../../../analysis/mod.dart';
import '../../../analyzer/protocol/analyzer_reading.dart';
import '../../../labels/cylinder_label.dart' show limitDepthMeters;
import '../../notifiers/settings_notifier.dart';
import '../../theme/safety_colors.dart';
import '../../theme/tokens.dart';
import '../../../data/models/gas_analysis.dart' show DesiredMix;

/// ppO2 (bar) the END and density tiles are evaluated at (MOD at this limit).
const double kAnalyzerReferencePpo2 = 1.4;

/// ppO2 (bar) tagged "DIL": the max ppO2 on a rebreather diluent.
const double kAnalyzerCcrDiluentPpo2 = 1.1;

/// `1.1`, `1.25`, `1.4`: at least one decimal, no trailing zeros beyond.
String fmtPpo2(double p) {
  var s = p.toStringAsFixed(2);
  if (s.endsWith('0')) s = s.substring(0, s.length - 1);
  return s;
}

/// Usable gas fractions from a reading, or null when O2/He can't be used
/// for planning numbers (no data or sensor error).
({double fo2, double fhe})? usableFractions(AnalyzerReading? r) {
  final o2 = r?.o2;
  final he = r?.he ?? 0;
  if (o2 == null || !o2.isFinite || o2 <= 0 || !he.isFinite) return null;
  return (fo2: o2 / 100, fhe: (he < 0 ? 0.0 : he) / 100);
}

class PlanningGrid extends StatefulWidget {
  const PlanningGrid({
    super.key,
    required this.reading,
    required this.settings,
    this.desired,
    this.wide = false,
  });

  final AnalyzerReading? reading;
  final SettingsNotifier settings;

  /// The desired mix picked on the save card, or null.
  final DesiredMix? desired;

  /// Wide layouts show the footnote under the grid, with no ⓘ.
  final bool wide;

  @override
  State<PlanningGrid> createState() => _PlanningGridState();
}

class _PlanningGridState extends State<PlanningGrid> {
  bool _showNote = false;

  static const _gap = Spacing.sm;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final settings = widget.settings;
    final reading = widget.reading;
    final f = usableFractions(reading);
    final tiles = <Widget>[];

    // The label's depth rule (#145): judged against the desired mix, except
    // on a hard mismatch, where the label names the analysed gas.
    int? depthDesiredO2;
    final d = widget.desired;
    if (d != null && f != null) {
      final hard = gradeMix(
            o2Percent: f.fo2 * 100,
            hePercent: f.fhe * 100,
            targetO2Percent: d.o2Percent,
            targetHePercent: d.hePercent,
          ).level ==
          MixMatchLevel.hard;
      depthDesiredO2 = hard ? null : d.o2Percent;
    }

    for (final p in settings.analyzerModPpo2s) {
      final isDil = (p - kAnalyzerCcrDiluentPpo2).abs() < 1e-9;
      String? value;
      String? unit;
      if (f != null) {
        final m = modMeters(f.fo2, p);
        // The same depth as the cylinder label: the nearest 3 m stop, or
        // the exact depth rounded down when the reading is above the
        // desired mix.
        final depth = m.isFinite && m > 0
            ? limitDepthMeters(reading!.o2!, p,
                desiredO2Percent: depthDesiredO2)
            : null;
        if (depth == null) {
          value = 'n/a';
        } else {
          value = '$depth';
          unit = 'm';
        }
      }
      tiles.add(_PlanningTile(
        key: ValueKey('analyzer-mod-${fmtPpo2(p)}'),
        label: 'MOD ${fmtPpo2(p)}',
        tag: isDil ? 'DIL' : null,
        value: value,
        unit: unit,
      ));
    }

    final refMod = f == null ? null : modMeters(f.fo2, kAnalyzerReferencePpo2);
    final refUsable = refMod != null && refMod.isFinite && refMod > 0;

    tiles.add(_PlanningTile(
      key: const ValueKey('analyzer-end'),
      label: 'END',
      value: refUsable
          ? endMeters(
              depthMeters: refMod,
              o2Fraction: f!.fo2,
              heFraction: f.fhe,
              countsOxygen: settings.endCountsOxygen,
            ).toStringAsFixed(0)
          : null,
      unit: refUsable ? 'm' : null,
    ));

    String? density;
    Color? densityColor;
    if (refUsable) {
      final ambientBar =
          kStandardAtmosphericPressureMbar / 1000.0 + refMod / 10.0;
      final g = mixDensityAt1Atm(f!.fo2, f.fhe) * ambientBar;
      density = g.toStringAsFixed(1);
      densityColor = switch (densityBand(g)) {
        DensityBand.green => SafetyColors.bandSafe,
        DensityBand.orange => SafetyColors.bandCaution,
        DensityBand.red => SafetyColors.bandOver,
      };
    }
    tiles.add(_PlanningTile(
      key: const ValueKey('analyzer-density'),
      label: 'Density',
      value: density,
      unit: density == null ? null : 'g/L',
      valueColor: densityColor,
    ));

    String? minDepth;
    String? minDepthUnit;
    if (f != null) {
      final m = minDepthMeters(f.fo2);
      if (m <= 0) {
        minDepth = 'surface';
      } else {
        minDepth = m.toStringAsFixed(0);
        minDepthUnit = 'm';
      }
    }
    tiles.add(_PlanningTile(
      key: const ValueKey('analyzer-min-depth'),
      label: 'Min. depth',
      value: minDepth,
      unit: minDepthUnit,
    ));

    final t = reading?.tempC;
    final tempOk = t != null && t.isFinite;
    tiles.add(_PlanningTile(
      key: const ValueKey('analyzer-temp'),
      label: 'Gas temp',
      value: tempOk ? t.toStringAsFixed(1) : null,
      unit: tempOk ? '°C' : null,
    ));
    final b = reading?.baroHpa;
    final baroOk = b != null && b.isFinite;
    tiles.add(_PlanningTile(
      key: const ValueKey('analyzer-baro'),
      label: 'Ambient',
      value: baroOk ? b.toStringAsFixed(0) : null,
      unit: baroOk ? 'hPa' : null,
    ));

    final endNote = settings.endCountsOxygen
        ? 'END counts O₂ and N₂ as narcotic.'
        : 'END counts only N₂ as narcotic.';
    final footnote = Text(
      'END and density at the 1.4 MOD. Seawater, 10 m/bar. $endNote '
      'Orientation only — plan with your own tools.',
      key: const ValueKey('analyzer-planning-footnote'),
      style: AppTypography.caption.copyWith(color: palette.textMuted),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'PLANNING',
                  style: AppTypography.label.copyWith(
                    color: palette.accentPrimary,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!widget.wide)
                IconButton(
                  key: const ValueKey('analyzer-planning-info'),
                  tooltip: 'About these numbers',
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  color: palette.textMuted,
                  icon: const Icon(Icons.info_outline),
                  onPressed: () => setState(() => _showNote = !_showNote),
                ),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          LayoutBuilder(builder: (context, c) {
            final w = (c.maxWidth - 3 * _gap) / 4;
            return Wrap(
              spacing: _gap,
              runSpacing: 10,
              children: [
                for (final tile in tiles) SizedBox(width: w, child: tile),
              ],
            );
          }),
          if (widget.wide || _showNote) ...[
            const SizedBox(height: Spacing.sm),
            footnote,
          ],
        ],
      ),
    );
  }
}

/// One planning tile: a small uppercase label (with an optional accent tag)
/// above a mono value and its unit. A null [value] shows `–`.
class _PlanningTile extends StatelessWidget {
  const _PlanningTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.tag,
    this.valueColor,
  });

  final String label;
  final String? value;
  final String? unit;
  final String? tag;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(text: label.toUpperCase()),
            if (tag != null)
              TextSpan(
                text: ' $tag',
                style: TextStyle(color: palette.accentPrimary),
              ),
          ]),
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: value ?? '–'),
              if (unit != null)
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: palette.textSecondary,
                  ),
                ),
            ]),
            style: AppTypography.readoutMd.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: valueColor ?? palette.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
