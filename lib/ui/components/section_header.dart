import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Uppercase 11px caption. Replaces ad-hoc section labels across
/// dive-detail tabs, settings, and other layered screens.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.label.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
