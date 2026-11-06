import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// One column of a hero readout: a tabular mono value with an optional unit
/// suffix above an uppercase micro-label. Centred on phones, left-aligned on
/// wider layouts. Put several in a [HeroStatRow].
class HeroStat extends StatelessWidget {
  const HeroStat({
    super.key,
    required this.value,
    this.unit,
    required this.label,
    this.valueColor,
    this.valueSize = 22,
    this.centered = false,
    this.valueKey,
  });

  final String value;
  final String? unit;
  final String label;

  /// Defaults to `palette.textPrimary`.
  final Color? valueColor;
  final double valueSize;
  final bool centered;

  /// Goes on the value [Text].
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment:
              centered ? MainAxisAlignment.center : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(value,
                  key: valueKey,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.readoutLg.copyWith(
                      fontSize: valueSize,
                      color: valueColor ?? palette.textPrimary)),
            ),
            if (unit != null) ...[
              const SizedBox(width: 2),
              Text(unit!,
                  style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: palette.textSecondary)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(label,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
                color: palette.textSecondary)),
      ],
    );
  }
}

/// A row of [HeroStat]s, equal widths, with a hairline divider between them.
class HeroStatRow extends StatelessWidget {
  const HeroStatRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              VerticalDivider(
                  width: 25, thickness: 1, color: palette.surfaceBezel),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }
}
