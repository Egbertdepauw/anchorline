import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'numeric_readout.dart';

/// A label + value display-only row. The label sits in a fixed-width
/// gutter on the left; the value is normal text by default, or a
/// numeric readout when [numeric] is true.
class DataRow extends StatelessWidget {
  const DataRow({
    super.key,
    required this.label,
    required this.value,
    this.numeric = false,
    this.labelWidth = 130,
  });

  final String label;
  final String value;
  final bool numeric;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: AppTypography.body.copyWith(color: scheme.outlineVariant),
            ),
          ),
          if (numeric)
            NumericReadout(value, size: ReadoutSize.sm)
          else
            Text(value,
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface,
                )),
        ],
      ),
    );
  }
}
