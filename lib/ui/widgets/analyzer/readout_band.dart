/// The Analyse tab's summary band: the measured mix name with the stability
/// pill, and the O₂, He and N₂ balance as hero stats.
library;

import 'package:flutter/material.dart';

import '../../../analysis/gas_naming.dart';
import '../../../analyzer/protocol/analyzer_reading.dart';
import '../../../analyzer/stability.dart';
import '../../components/hero_stat.dart';
import '../../theme/data_colors.dart';
import '../../theme/safety_colors.dart';
import '../../theme/tokens.dart';

/// One-decimal readout: `--.-` before data, `***.*` on a sensor error
/// (what the SOLO itself shows).
String fmtAnalyzerPercent(double? v) {
  if (v == null) return '--.-';
  if (!v.isFinite) return '***.*';
  return v.toStringAsFixed(1);
}

class ReadoutBand extends StatelessWidget {
  const ReadoutBand({
    super.key,
    required this.reading,
    required this.stability,
    this.wide = false,
  });

  final AnalyzerReading? reading;
  final ReadingStability stability;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final o2 = reading?.o2;
    final he = reading?.he ?? 0;
    final usable = o2 != null && o2.isFinite && he.isFinite;
    final name = usable ? gasMixNameDecimal(o2, he) : '—';
    // N₂ is what is left: unknown without data, starred on a sensor error.
    final n2 = usable
        ? (100 - o2 - he).toStringAsFixed(1)
        : (o2 == null ? '--.-' : '***.*');

    final valueSize = wide ? 44.0 : 30.0;
    final nameSize = wide ? 34.0 : 26.0;

    return Container(
      color: palette.surfaceRaised,
      padding: EdgeInsets.fromLTRB(
          Spacing.lg, 10, Spacing.lg, wide ? Spacing.lg : 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    name,
                    key: const ValueKey('analyzer-mix'),
                    style: AppTypography.display.copyWith(
                      fontSize: nameSize,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Spacing.md),
              StabilityPill(stability: stability),
            ],
          ),
          const SizedBox(height: 6),
          HeroStatRow(children: [
            HeroStat(
              valueKey: const ValueKey('analyzer-o2'),
              value: fmtAnalyzerPercent(o2),
              unit: '%',
              label: 'OXYGEN',
              valueColor: palette.accentPrimary,
              valueSize: valueSize,
              centered: true,
            ),
            HeroStat(
              valueKey: const ValueKey('analyzer-he'),
              value: fmtAnalyzerPercent(reading?.he),
              unit: '%',
              label: 'HELIUM',
              valueColor: DataColors.helium,
              valueSize: valueSize,
              centered: true,
            ),
            HeroStat(
              valueKey: const ValueKey('analyzer-n2'),
              value: n2,
              unit: '%',
              label: 'N₂ BALANCE',
              valueSize: valueSize,
              centered: true,
            ),
          ]),
        ],
      ),
    );
  }
}

/// NO DATA / SETTLING / STABLE / SENSOR ERROR.
class StabilityPill extends StatelessWidget {
  const StabilityPill({super.key, required this.stability});

  final ReadingStability stability;

  static String labelFor(ReadingStability s) => switch (s) {
        ReadingStability.noData => 'NO DATA',
        ReadingStability.settling => 'SETTLING',
        ReadingStability.stable => 'STABLE',
        ReadingStability.sensorError => 'SENSOR ERROR',
      };

  @override
  Widget build(BuildContext context) {
    final color = switch (stability) {
      ReadingStability.noData => context.palette.textMuted,
      ReadingStability.settling => SafetyColors.warning,
      ReadingStability.stable => SafetyColors.success,
      ReadingStability.sensorError => SafetyColors.danger,
    };
    final icon = switch (stability) {
      ReadingStability.noData => Icons.remove,
      ReadingStability.settling => Icons.radio_button_unchecked,
      ReadingStability.stable => Icons.circle,
      ReadingStability.sensorError => Icons.error_outline,
    };
    return Container(
      key: const ValueKey('analyzer-pill'),
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.xs + 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: const BorderRadius.all(Radius.circular(999)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: Spacing.sm),
          Text(
            labelFor(stability),
            style: AppTypography.label.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
