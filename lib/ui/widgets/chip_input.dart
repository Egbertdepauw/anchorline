import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class ChipInput extends StatefulWidget {
  final List<String> values;
  final List<String> autocompleteOptions;
  final void Function(List<String> values) onChanged;
  final String hintText;

  /// Accent colour for each chip's outline + label. Falls back to the
  /// theme primary if not provided. Buddies / tags / other taxonomies
  /// each pass their own so they read as distinct visual classes.
  final Color? accentColor;

  const ChipInput({
    super.key,
    required this.values,
    required this.autocompleteOptions,
    required this.onChanged,
    this.hintText = 'Add…',
    this.accentColor,
  });

  @override
  State<ChipInput> createState() => _ChipInputState();
}

class _ChipInputState extends State<ChipInput> {
  void _add(String raw, TextEditingController controller) {
    final v = raw.trim();
    if (v.isEmpty || widget.values.contains(v)) {
      controller.clear();
      return;
    }
    widget.onChanged([...widget.values, v]);
    controller.clear();
  }

  void _remove(String v) {
    widget.onChanged(widget.values.where((x) => x != v).toList());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = widget.accentColor ?? scheme.primary;
    final available = widget.autocompleteOptions
        .where((o) => !widget.values.contains(o))
        .toList();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final v in widget.values)
          Chip(
            label: Text(v,
                style: AppTypography.caption.copyWith(color: accent)),
            backgroundColor: Colors.transparent,
            side: BorderSide(color: accent),
            shape: const RoundedRectangleBorder(borderRadius: Radii.chipBr),
            onDeleted: () => _remove(v),
            deleteIcon: Icon(Icons.close, size: 14, color: accent),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        SizedBox(
          width: 220,
          child: Autocomplete<String>(
            optionsBuilder: (TextEditingValue tev) {
              // Empty text → show every still-available option (filtering
              // out values already chipped). Lets the field act as a
              // discovery dropdown when the user hasn't typed yet.
              if (tev.text.isEmpty) return available;
              return available.where(
                  (o) => o.toLowerCase().contains(tev.text.toLowerCase()));
            },
            onSelected: (selected) {
              if (!widget.values.contains(selected)) {
                widget.onChanged([...widget.values, selected]);
              }
            },
            fieldViewBuilder:
                (context, textController, focusNode, onSubmitted) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: TextField(
                      controller: textController,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        hintText: widget.hintText,
                        isDense: true,
                      ),
                      onSubmitted: (v) => _add(v, textController),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 20),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Add',
                    onPressed: () => _add(textController.text, textController),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
