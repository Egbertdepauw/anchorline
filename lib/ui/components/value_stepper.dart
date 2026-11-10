import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// − / value / + around an integer kept between [min] and [max]; a button
/// that would pass a limit is disabled. Keys are `$keyPrefix-dec`,
/// `$keyPrefix-value` and `$keyPrefix-inc`.
class ValueStepper extends StatelessWidget {
  const ValueStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    this.step = 1,
    this.unit,
    required this.keyPrefix,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final int step;
  final String? unit;
  final String keyPrefix;
  final ValueChanged<int> onChanged;

  static const _target = BoxConstraints(minWidth: 44, minHeight: 44);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: ValueKey('$keyPrefix-dec'),
          constraints: _target,
          icon: const Icon(Icons.remove),
          onPressed: value > min
              ? () => onChanged((value - step).clamp(min, max))
              : null,
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: Spacing.xl),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$value',
                  key: ValueKey('$keyPrefix-value'),
                  textAlign: TextAlign.center,
                  style: AppTypography.readoutMd),
              if (unit != null) ...[
                const SizedBox(width: 2),
                Text(unit!,
                    style: TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 12,
                        color: palette.textSecondary)),
              ],
            ],
          ),
        ),
        IconButton(
          key: ValueKey('$keyPrefix-inc'),
          constraints: _target,
          icon: const Icon(Icons.add),
          onPressed: value < max
              ? () => onChanged((value + step).clamp(min, max))
              : null,
        ),
      ],
    );
  }
}
