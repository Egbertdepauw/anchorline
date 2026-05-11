import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Secondary action button. Outlined, no fill, accent border.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = icon == null
        ? Text(label.toUpperCase())
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: Spacing.sm),
              Text(label.toUpperCase()),
            ],
          );
    return OutlinedButton(onPressed: onPressed, child: child);
  }
}
