import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum ReadoutSize { sm, md, lg }

/// JetBrains Mono numeric readout with tabular figures. Designed for
/// stat values where character columns must align (depth tables, time
/// rows, cell mV ladders).
class NumericReadout extends StatelessWidget {
  const NumericReadout(
    this.value, {
    super.key,
    this.size = ReadoutSize.md,
    this.color,
  });

  final String value;
  final ReadoutSize size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = switch (size) {
      ReadoutSize.sm => AppTypography.readoutSm,
      ReadoutSize.md => AppTypography.readoutMd,
      ReadoutSize.lg => AppTypography.readoutLg,
    };
    return Text(
      value,
      style: style.copyWith(
        color: color ?? Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}
