import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'numeric_readout.dart';

/// One labelled stat tile: a small uppercase label above a tabular
/// numeric readout. Used in the Dive Detail stats row and anywhere a
/// dive-computer-style metric needs to appear.
///
/// [unit] is rendered in the label position alongside [label] (e.g.
/// "DEPTH m"). [hint] is an optional auxiliary mini-readout under the
/// main value (e.g. "min/max" in fine print).
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.hint,
    this.valueColor,
    this.size = ReadoutSize.md,
  });

  final String label;
  final String value;
  final String? unit;
  final String? hint;
  final Color? valueColor;
  final ReadoutSize size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fullLabel = unit == null ? label : '$label  $unit';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          fullLabel.toUpperCase(),
          style: AppTypography.label.copyWith(color: scheme.outlineVariant),
        ),
        const SizedBox(height: Spacing.xs),
        NumericReadout(value, size: size, color: valueColor),
        if (hint != null) ...[
          const SizedBox(height: 2),
          Text(
            hint!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(color: scheme.outlineVariant),
          ),
        ],
      ],
    );
  }
}
