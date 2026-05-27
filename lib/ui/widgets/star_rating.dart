import 'package:flutter/material.dart';

class StarRating extends StatelessWidget {
  final int? value; // 1-5 or null
  final void Function(int? value)? onChanged;
  final double size;
  final bool readOnly;

  const StarRating({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 24,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    if (readOnly) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.5),
              child: Icon(
                i <= (value ?? 0) ? Icons.star : Icons.star_outline,
                size: size,
                color: color.withValues(alpha: i <= (value ?? 0) ? 1.0 : 0.3),
              ),
            ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: size,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(
              minWidth: size + 4,
              minHeight: size + 4,
            ),
            icon: Icon(
              i <= (value ?? 0) ? Icons.star : Icons.star_outline,
              color: color,
            ),
            onPressed: () {
              if (value == i) {
                onChanged?.call(null);
              } else {
                onChanged?.call(i);
              }
            },
          ),
      ],
    );
  }
}
