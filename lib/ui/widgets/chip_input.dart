import 'package:flutter/material.dart';

class ChipInput extends StatefulWidget {
  final List<String> initialValues;
  final List<String> autocompleteOptions;
  final void Function(List<String> values) onChanged;
  final String hintText;

  const ChipInput({
    super.key,
    required this.initialValues,
    required this.autocompleteOptions,
    required this.onChanged,
    this.hintText = 'Add…',
  });

  @override
  State<ChipInput> createState() => _ChipInputState();
}

class _ChipInputState extends State<ChipInput> {
  late List<String> _values;

  @override
  void initState() {
    super.initState();
    _values = [...widget.initialValues];
  }

  void _add(String raw, TextEditingController controller) {
    final v = raw.trim();
    if (v.isEmpty || _values.contains(v)) {
      controller.clear();
      return;
    }
    setState(() => _values.add(v));
    controller.clear();
    widget.onChanged(_values);
  }

  void _remove(String v) {
    setState(() => _values.remove(v));
    widget.onChanged(_values);
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.autocompleteOptions
        .where((o) => !_values.contains(o))
        .toList();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final v in _values)
          Chip(
            label: Text(v),
            onDeleted: () => _remove(v),
            deleteIcon: const Icon(Icons.close, size: 16),
          ),
        SizedBox(
          width: 160,
          child: Autocomplete<String>(
            optionsBuilder: (TextEditingValue tev) {
              if (tev.text.isEmpty) return const Iterable<String>.empty();
              return available.where(
                  (o) => o.toLowerCase().contains(tev.text.toLowerCase()));
            },
            onSelected: (selected) {
              setState(() {
                if (!_values.contains(selected)) _values.add(selected);
              });
              widget.onChanged(_values);
            },
            fieldViewBuilder:
                (context, textController, focusNode, onSubmitted) {
              return TextField(
                controller: textController,
                focusNode: focusNode,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  isDense: true,
                ),
                onSubmitted: (v) => _add(v, textController),
              );
            },
          ),
        ),
      ],
    );
  }
}
