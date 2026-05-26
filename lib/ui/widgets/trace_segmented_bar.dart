/// Segmented bar that toggles which traces draw on the profile chart.
library;

import 'package:flutter/material.dart';

import '../components/status_dot.dart';
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

const _segmentData = <TraceType, ({String label, Color color})>{
  TraceType.ppo2: (label: 'PPO2', color: Color(0xFFFFCC66)),
  TraceType.setpoint: (label: 'Setpoint', color: Color(0xFFA0AEB6)),
  TraceType.cells: (label: 'Cells', color: Color(0xFF4ADE80)),
  TraceType.deco: (label: 'Deco', color: Color(0xFFF39C12)),
  TraceType.tanks: (label: 'Tanks', color: Color(0xFF60A5FA)),
  TraceType.gasChanges: (label: 'Gas', color: Color(0xFF60A5FA)),
  TraceType.density: (label: 'Density', color: Color(0xFFE3E6EB)),
  TraceType.end: (label: 'END', color: Color(0xFFE3E6EB)),
  TraceType.gf99: (label: 'GF99', color: Color(0xFF9333EA)),
  TraceType.ceiling: (label: 'Ceiling', color: Color(0xFFEAB308)),
  // Water temperature trace — cyan, evocative of cold water and
  // visually distinct from the existing depth (blue) and tank
  // (light-blue) traces.
  TraceType.waterTemp: (label: 'Temp', color: Color(0xFF4DD0E1)),
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
            for (final entry in _segmentData.entries) ...[
              _Segment(
                label: entry.value.label,
                dotColor: entry.value.color,
                selected: visibleTraces.contains(entry.key),
                onTap: () => onToggle(entry.key),
                scheme: scheme,
              ),
              if (entry.key != _segmentData.keys.last)
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
