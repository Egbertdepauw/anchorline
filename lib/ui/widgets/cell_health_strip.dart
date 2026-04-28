import 'package:flutter/material.dart';

import '../../analysis/cell_health.dart';

class CellHealthStrip extends StatelessWidget {
  final CellHealth health;
  final int slot;

  const CellHealthStrip({
    super.key,
    required this.health,
    required this.slot,
  });

  @override
  Widget build(BuildContext context) {
    final hasAge = health.ageMonths != null;
    final hasMv = health.mvStatus != CellMvStatus.insufficientData;
    if (!hasAge && !hasMv) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasAge) _ageBar(theme),
        if (hasAge) const SizedBox(height: 8),
        Row(children: [_mvPill(theme)]),
      ],
    );
  }

  Widget _ageBar(ThemeData theme) {
    final months = health.ageMonths!;
    final fraction = (months / 12.0).clamp(0.0, 1.0);
    final Color color;
    if (months < 8) {
      color = Colors.green;
    } else if (months < 12) {
      color = Colors.amber;
    } else {
      color = Colors.redAccent;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${months.toStringAsFixed(1)} mo / 12 mo  ·  ${health.diveCount} dives',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _mvPill(ThemeData theme) {
    final (emoji, label, color) = switch (health.mvStatus) {
      CellMvStatus.healthy => ('🟢', 'Healthy', Colors.green),
      CellMvStatus.watch => ('🟡', 'Watch', Colors.amber),
      CellMvStatus.replace => ('🔴', 'Replace', Colors.redAccent),
      CellMvStatus.insufficientData => ('⚪', 'Insufficient data', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        '$emoji  $label',
        style: theme.textTheme.labelMedium,
      ),
    );
  }
}
