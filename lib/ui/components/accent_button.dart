import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Primary action button. Hard-edge, sodium-vapor fill, uppercase label.
/// Wraps FilledButton with the design-system defaults baked in.
class AccentButton extends StatelessWidget {
  const AccentButton({
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
    return FilledButton(onPressed: onPressed, child: child);
  }
}
