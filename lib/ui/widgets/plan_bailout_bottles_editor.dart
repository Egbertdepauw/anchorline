/// Editor for the plan's per-bottle bailout list.
///
/// Each row exposes:
///   • the gas (dropdown of the plan's defined gases)
///   • water capacity (litres)
///   • fill pressure (bar)
///   • a delete button
///
/// All four fields are editable after the bottle is added — early
/// versions only let the diver delete and re-add, which made
/// experimenting with a different cylinder size painful.
library;

import 'package:flutter/material.dart';

import '../../data/models/dive_plan.dart';
import '../theme/tokens.dart';

class PlanBailoutBottlesEditor extends StatelessWidget {
  const PlanBailoutBottlesEditor({
    super.key,
    required this.gases,
    required this.bottles,
    required this.onAdd,
    required this.onRemove,
    required this.onReplace,
  });

  final List<DivePlanGas> gases;
  final List<DivePlanBailoutBottle> bottles;
  final ValueChanged<DivePlanBailoutBottle> onAdd;
  final ValueChanged<int> onRemove;
  final void Function(int idx, DivePlanBailoutBottle b) onReplace;

  static String mixLabel(DivePlanGas g) {
    if (g.heliumPercent > 0) {
      return 'Tx${g.oxygenPercent}/${g.heliumPercent}';
    }
    if (g.oxygenPercent == 21) return 'Air';
    return 'EAN${g.oxygenPercent}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('BAILOUT BOTTLES', style: AppTypography.label),
        if (gases.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.sm),
            child: Text(
              'Add a gas first — bottles reference the plan\'s gas list.',
              style: AppTypography.caption,
            ),
          ),
        for (var i = 0; i < bottles.length; i++)
          _BottleRow(
            key: ValueKey('bottle-$i'),
            index: i,
            bottle: bottles[i],
            gases: gases,
            onReplace: onReplace,
            onRemove: onRemove,
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('add-bottle'),
            icon: const Icon(Icons.add),
            label: const Text('Add bailout bottle'),
            onPressed: gases.isEmpty
                ? null
                : () => onAdd(const DivePlanBailoutBottle(
                    gasMixIndex: 0,
                    waterCapacityL: 5.7,
                    fillPressureBar: 200)),
          ),
        ),
      ],
    );
  }
}

class _BottleRow extends StatefulWidget {
  const _BottleRow({
    super.key,
    required this.index,
    required this.bottle,
    required this.gases,
    required this.onReplace,
    required this.onRemove,
  });

  final int index;
  final DivePlanBailoutBottle bottle;
  final List<DivePlanGas> gases;
  final void Function(int idx, DivePlanBailoutBottle b) onReplace;
  final ValueChanged<int> onRemove;

  @override
  State<_BottleRow> createState() => _BottleRowState();
}

class _BottleRowState extends State<_BottleRow> {
  late final TextEditingController _capCtrl;
  late final TextEditingController _pressCtrl;
  final FocusNode _capFocus = FocusNode();
  final FocusNode _pressFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _capCtrl = TextEditingController(
        text: widget.bottle.waterCapacityL.toStringAsFixed(1));
    _pressCtrl =
        TextEditingController(text: '${widget.bottle.fillPressureBar}');
  }

  @override
  void didUpdateWidget(_BottleRow old) {
    super.didUpdateWidget(old);
    final newCap = widget.bottle.waterCapacityL.toStringAsFixed(1);
    if (!_capFocus.hasFocus && _capCtrl.text != newCap) {
      _capCtrl.text = newCap;
    }
    final newPress = '${widget.bottle.fillPressureBar}';
    if (!_pressFocus.hasFocus && _pressCtrl.text != newPress) {
      _pressCtrl.text = newPress;
    }
  }

  @override
  void dispose() {
    _capCtrl.dispose();
    _pressCtrl.dispose();
    _capFocus.dispose();
    _pressFocus.dispose();
    super.dispose();
  }

  void _emit({int? gasMixIndex, double? capacityL, int? pressureBar}) {
    widget.onReplace(
      widget.index,
      DivePlanBailoutBottle(
        gasMixIndex: gasMixIndex ?? widget.bottle.gasMixIndex,
        waterCapacityL: capacityL ?? widget.bottle.waterCapacityL,
        fillPressureBar: pressureBar ?? widget.bottle.fillPressureBar,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Clamp the dropdown's value to a valid index — if a gas the bottle
    // referenced was deleted, fall back to 0 rather than crash the
    // assertion `value must be one of items`.
    final safeGasIndex = widget.bottle.gasMixIndex < widget.gases.length
        ? widget.bottle.gasMixIndex
        : 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                key: ValueKey('bottle-${widget.index}-gas'),
                isDense: true,
                value: safeGasIndex,
                items: [
                  for (var i = 0; i < widget.gases.length; i++)
                    DropdownMenuItem<int>(
                      value: i,
                      child: Text(
                        PlanBailoutBottlesEditor.mixLabel(widget.gases[i]),
                        style: AppTypography.readoutSm,
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) _emit(gasMixIndex: v);
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: TextField(
              controller: _capCtrl,
              focusNode: _capFocus,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                isDense: true,
                suffixText: 'L',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              ),
              onChanged: (s) {
                final v = double.tryParse(s);
                if (v != null && v > 0) _emit(capacityL: v);
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 76,
            child: TextField(
              controller: _pressCtrl,
              focusNode: _pressFocus,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                suffixText: 'bar',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              ),
              onChanged: (s) {
                final v = int.tryParse(s);
                if (v != null && v > 0) _emit(pressureBar: v);
              },
            ),
          ),
          IconButton(
            tooltip: 'Remove bottle',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => widget.onRemove(widget.index),
          ),
        ],
      ),
    );
  }
}
