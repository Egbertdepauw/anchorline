import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Hard-edge 2px card with surface.card background.
///
/// Use [withBezel] for the "instrument" look — a 1px bezel outline
/// using surface.bezel. Optional [padding] (default: Spacing.md).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Spacing.md),
    this.withBezel = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool withBezel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: Radii.cardBr,
        border: withBezel ? Border.all(color: scheme.outline) : null,
      ),
      padding: padding,
      child: child,
    );
  }
}
