/// Editor for the plan's gas list. Each row exposes O₂ / He as
/// numeric inputs plus a diluent toggle + delete. Reordering is
/// intentionally absent: gas index stability is critical (segments
/// reference by index).
library;

import 'package:flutter/material.dart';

import '../../data/models/dive_plan.dart';
import '../theme/tokens.dart';

class PlanGasesEditor extends StatelessWidget {
  const PlanGasesEditor({
    super.key,
    required this.gases,
    required this.onAdd,
    required this.onRemove,
    required this.onReplace,
  });

  final List<DivePlanGas> gases;
  final ValueChanged<DivePlanGas> onAdd;
  final ValueChanged<int> onRemove;
  final void Function(int idx, DivePlanGas g) onReplace;

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
        Text('GASES', style: AppTypography.label),
        for (var i = 0; i < gases.length; i++)
          _GasRow(
            key: ValueKey('gas-$i'),
            index: i,
            gas: gases[i],
            onReplace: onReplace,
            onRemove: onRemove,
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('add-gas'),
            icon: const Icon(Icons.add),
            label: const Text('Add gas'),
            onPressed: () => onAdd(const DivePlanGas(
              oxygenPercent: 21,
              heliumPercent: 0,
              isDiluent: true,
            )),
          ),
        ),
      ],
    );
  }
}

class _GasRow extends StatefulWidget {
  const _GasRow({
    super.key,
    required this.index,
    required this.gas,
    required this.onReplace,
    required this.onRemove,
  });

  final int index;
  final DivePlanGas gas;
  final void Function(int idx, DivePlanGas g) onReplace;
  final ValueChanged<int> onRemove;

  @override
  State<_GasRow> createState() => _GasRowState();
}

class _GasRowState extends State<_GasRow> {
  late final TextEditingController _o2Ctrl;
  late final TextEditingController _heCtrl;
  final FocusNode _o2Focus = FocusNode();
  final FocusNode _heFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _o2Ctrl = TextEditingController(text: '${widget.gas.oxygenPercent}');
    _heCtrl = TextEditingController(text: '${widget.gas.heliumPercent}');
  }

  @override
  void didUpdateWidget(_GasRow old) {
    super.didUpdateWidget(old);
    final newO2 = '${widget.gas.oxygenPercent}';
    if (!_o2Focus.hasFocus && _o2Ctrl.text != newO2) {
      _o2Ctrl.text = newO2;
    }
    final newHe = '${widget.gas.heliumPercent}';
    if (!_heFocus.hasFocus && _heCtrl.text != newHe) {
      _heCtrl.text = newHe;
    }
  }

  @override
  void dispose() {
    _o2Ctrl.dispose();
    _heCtrl.dispose();
    _o2Focus.dispose();
    _heFocus.dispose();
    super.dispose();
  }

  void _emit({int? o2, int? he, bool? isDiluent}) {
    widget.onReplace(
      widget.index,
      DivePlanGas(
        oxygenPercent: (o2 ?? widget.gas.oxygenPercent).clamp(1, 100),
        heliumPercent: (he ?? widget.gas.heliumPercent).clamp(0, 99),
        isDiluent: isDiluent ?? widget.gas.isDiluent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: TextField(
              controller: _o2Ctrl,
              focusNode: _o2Focus,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                suffixText: '%',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              ),
              onChanged: (s) {
                final v = int.tryParse(s);
                if (v != null) _emit(o2: v);
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text('/'),
          ),
          SizedBox(
            width: 64,
            child: TextField(
              controller: _heCtrl,
              focusNode: _heFocus,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                suffixText: '%',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              ),
              onChanged: (s) {
                final v = int.tryParse(s);
                if (v != null) _emit(he: v);
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Diluent', style: AppTypography.caption),
              value: widget.gas.isDiluent,
              onChanged: (v) => _emit(isDiluent: v),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => widget.onRemove(widget.index),
          ),
        ],
      ),
    );
  }
}
