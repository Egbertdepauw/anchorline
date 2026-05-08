import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/annotation.dart';

/// Editor for the per-dive `weights` list (the structured replacement
/// for the legacy `weight_system` free-text field). Each row carries a
/// kg amount and a free-text description, e.g. `1.5kg, "underweight"`.
class WeightsEditor extends StatefulWidget {
  final List<Weight> weights;
  final void Function(List<Weight>) onChanged;

  const WeightsEditor({
    super.key,
    required this.weights,
    required this.onChanged,
  });

  @override
  State<WeightsEditor> createState() => _WeightsEditorState();
}

class _WeightsEditorState extends State<WeightsEditor> {
  late List<_RowControllers> _rows;

  @override
  void initState() {
    super.initState();
    _rows = _buildRows(widget.weights);
  }

  @override
  void didUpdateWidget(covariant WeightsEditor old) {
    super.didUpdateWidget(old);
    // Re-sync when the parent loaded a different annotation (e.g. after
    // initial async load). Detect via length mismatch to avoid clobbering
    // the user's in-flight edits.
    if (old.weights.length != widget.weights.length) {
      for (final r in _rows) {
        r.dispose();
      }
      _rows = _buildRows(widget.weights);
    }
  }

  List<_RowControllers> _buildRows(List<Weight> ws) => [
        for (final w in ws)
          _RowControllers(
            desc: TextEditingController(text: w.description),
            weight: TextEditingController(text: _formatKg(w.weightKg)),
          ),
      ];

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  static String _formatKg(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }

  void _emit() {
    final next = <Weight>[];
    for (final r in _rows) {
      final kg = double.tryParse(r.weight.text.replaceAll(',', '.'));
      if (kg == null || kg <= 0) continue;
      next.add(Weight(
        weightKg: kg,
        description: r.desc.text.trim(),
      ));
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Weights', style: Theme.of(context).textTheme.titleSmall),
        if (_rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'No weights recorded.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.55),
              ),
            ),
          ),
        for (var i = 0; i < _rows.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _rows[i].desc,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _emit(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _rows[i].weight,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'kg',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _emit(),
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () {
                  setState(() {
                    _rows[i].dispose();
                    _rows.removeAt(i);
                  });
                  _emit();
                },
              ),
            ]),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add weight'),
            onPressed: () {
              setState(() {
                _rows.add(_RowControllers(
                  desc: TextEditingController(),
                  weight: TextEditingController(),
                ));
              });
            },
          ),
        ),
      ],
    );
  }
}

class _RowControllers {
  final TextEditingController desc;
  final TextEditingController weight;
  _RowControllers({required this.desc, required this.weight});

  void dispose() {
    desc.dispose();
    weight.dispose();
  }
}
