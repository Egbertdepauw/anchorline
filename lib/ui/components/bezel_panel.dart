import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 1px bezel outline, no fill. Wraps charts, instruments, longitudinal
/// views — anything that should read as an instrument bezel rather
/// than a card.
class BezelPanel extends StatelessWidget {
  const BezelPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Spacing.md),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: Radii.cardBr,
        border: Border.all(color: scheme.outline),
      ),
      padding: padding,
      child: child,
    );
  }
}
