import 'package:flutter/material.dart';

class StarRating extends StatelessWidget {
  final int? value; // 1-5 or null
  final void Function(int? value) onChanged;
  final double size;

  const StarRating({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
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
              color: Theme.of(context).colorScheme.primary,
            ),
            onPressed: () {
              if (value == i) {
                onChanged(null);
              } else {
                onChanged(i);
              }
            },
          ),
      ],
    );
  }
}
