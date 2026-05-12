/// Wrapping row of toggles for profile traces.
library;

import 'package:flutter/material.dart';

import '../components/status_dot.dart';
import 'trace_segmented_bar.dart' show TraceType;
import '../theme/tokens.dart';

/// One toggle's display data — the label shown on the chip, and the
/// colour the corresponding trace renders with on the chart (used for
/// the small leading [StatusDot] so the diver can correlate chip ↔
/// trace at a glance).
const _traceChipData = <TraceType, ({String label, Color color})>{
  TraceType.ppo2: (label: 'PPO2', color: Color(0xFFFFCC66)),
  TraceType.setpoint: (label: 'Setpoint', color: Color(0xFFA0AEB6)),
  TraceType.cells: (label: 'Cells', color: Color(0xFF4ADE80)),
  TraceType.deco: (label: 'Deco', color: Color(0xFFF39C12)),
  TraceType.tanks: (label: 'Tanks', color: Color(0xFF60A5FA)),
  TraceType.gasChanges: (label: 'Gas', color: Color(0xFF60A5FA)),
};

/// A [Wrap] of toggle chips, one per [TraceType].
///
/// The chip body uses the design-system colours (accent border when
/// selected, bezel + muted text when deselected). A small 8px dot in
/// the trace's chart colour sits before the label so the user can
/// still see which colour each trace is drawn in.
class TraceToggleChips extends StatelessWidget {
  final Set<TraceType> visibleTraces;
  final ValueChanged<TraceType> onToggle;

  const TraceToggleChips({
    super.key,
    required this.visibleTraces,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.sm),
      child: Wrap(
        spacing: Spacing.sm,
        runSpacing: Spacing.xs,
        children: [
          for (final entry in _traceChipData.entries)
            _TraceChip(
              label: entry.value.label,
              dotColor: entry.value.color,
              selected: visibleTraces.contains(entry.key),
              onTap: () => onToggle(entry.key),
              scheme: scheme,
            ),
        ],
      ),
    );
  }
}

class _TraceChip extends StatelessWidget {
  const _TraceChip({
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
    final borderColor = selected ? scheme.primary : scheme.outline;
    final labelColor = selected ? scheme.onSurface : scheme.outlineVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.chipBr,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? scheme.surfaceContainer : Colors.transparent,
          border: Border.all(color: borderColor),
          borderRadius: Radii.chipBr,
        ),
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm, vertical: Spacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The dot is full-colour when the trace is visible (matches
            // the chart trace), muted when off (still readable, doesn't
            // shout).
            StatusDot(
              color: selected ? dotColor : dotColor.withValues(alpha: 0.35),
            ),
            const SizedBox(width: Spacing.xs),
            Text(
              label,
              style: AppTypography.caption.copyWith(color: labelColor),
            ),
          ],
        ),
      ),
    );
  }
}
