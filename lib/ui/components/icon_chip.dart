import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A small filter/status chip with an optional leading icon. Used for
/// dive tags, filter toggles, status badges.
class IconChip extends StatelessWidget {
  const IconChip({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? scheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          border: Border.all(color: scheme.outline),
          borderRadius: Radii.chipBr,
        ),
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm, vertical: Spacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: Spacing.xs),
            ],
            Text(label,
                style: AppTypography.caption.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}
