/// Segmented bar that toggles which traces draw on the profile chart.
library;

import 'package:flutter/material.dart';

import '../components/status_dot.dart';
import '../theme/data_colors.dart';
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';

/// The set of data traces that can be toggled on/off in the profile chart.
enum TraceType {
  ppo2,
  setpoint,
  deco,
  cells,
  tanks,
  gasChanges,
  density,
  end,
  gf99,
  ceiling,
  waterTemp,
}

const _segmentLabels = <TraceType, String>{
  TraceType.ppo2: 'PPO2',
  TraceType.setpoint: 'Setpoint',
  TraceType.cells: 'Cells',
  TraceType.deco: 'Deco',
  TraceType.tanks: 'Tanks',
  TraceType.gasChanges: 'Gas',
  TraceType.density: 'Density',
  TraceType.end: 'END',
  TraceType.gf99: 'GF99',
  TraceType.ceiling: 'Ceiling',
  TraceType.waterTemp: 'Temp',
};

/// The legend swatch colour for [type]: the colour the profile chart
/// draws that trace in.
Color traceLegendColor(TraceType type, ThemePalette palette) => switch (type) {
      TraceType.ppo2 => palette.chartTracePpo2,
      TraceType.setpoint => palette.chartTraceSetpoint,
      TraceType.cells => palette.cell1,
      TraceType.deco => SafetyColors.warning,
      TraceType.tanks => DataColors.tanks.first,
      TraceType.gasChanges => SafetyColors.info,
      TraceType.density => palette.textPrimary,
      TraceType.end => palette.textPrimary,
      TraceType.gf99 => DataColors.gf99,
      TraceType.ceiling => DataColors.ceiling,
      TraceType.waterTemp => DataColors.waterTemp,
    };

/// Connected segmented control of [TraceType] toggles. Ten segments share
/// a single rounded outline with 1-px dividers; selected segments tint
/// up. On narrow screens the bar overflows right and scrolls
/// horizontally.
class TraceSegmentedBar extends StatelessWidget {
  final Set<TraceType> visibleTraces;
  final ValueChanged<TraceType> onToggle;

  const TraceSegmentedBar({
    super.key,
    required this.visibleTraces,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.sm),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outline),
          borderRadius: Radii.chipBr,
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in _segmentLabels.entries) ...[
              _Segment(
                label: entry.value,
                dotColor: traceLegendColor(entry.key, context.palette),
                selected: visibleTraces.contains(entry.key),
                onTap: () => onToggle(entry.key),
                scheme: scheme,
              ),
              if (entry.key != _segmentLabels.keys.last)
                Container(width: 1, color: scheme.outline),
            ],
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.dotColor,
    required this.selected,
    required this.onTap,
    required this.scheme,
  });

  final String label;
  final Color dotColor;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected
            ? scheme.primary.withValues(alpha: 0.18)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm + 2, vertical: Spacing.xs + 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusDot(
              color: selected ? dotColor : dotColor.withValues(alpha: 0.4),
            ),
            const SizedBox(width: Spacing.xs),
            Text(
              label,
              style: AppTypography.caption.copyWith(
                color: selected ? scheme.onSurface : scheme.outlineVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
