/// Horizontal scrollable row of [FilterChip]s for toggling profile traces.
library;

import 'package:flutter/material.dart';
import '../notifiers/dive_detail_notifier.dart';

const _traceChipData = <TraceType, ({String label, Color color})>{
  TraceType.ppo2: (label: 'PPO2', color: Color(0xFF66BB6A)),
  TraceType.setpoint: (label: 'Setpoint', color: Color(0xFFFF9800)),
  TraceType.cells: (label: 'Cells', color: Color(0xFFEF5350)),
  TraceType.deco: (label: 'Deco', color: Color(0xFFFF9800)),
  TraceType.tanks: (label: 'Tanks', color: Color(0xFF90A4AE)),
};

/// A horizontally scrollable row of [FilterChip] widgets, one per [TraceType].
///
/// Chips show as selected (coloured) when their [TraceType] is in
/// [visibleTraces]. Tapping any chip calls [onToggle] with that type.
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (final entry in _traceChipData.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(entry.value.label),
                selected: visibleTraces.contains(entry.key),
                onSelected: (_) => onToggle(entry.key),
                selectedColor: entry.value.color.withValues(alpha: 0.3),
                checkmarkColor: entry.value.color,
                side: BorderSide(
                  color: visibleTraces.contains(entry.key)
                      ? entry.value.color
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.2),
                ),
                labelStyle: TextStyle(
                  color: visibleTraces.contains(entry.key)
                      ? entry.value.color
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
