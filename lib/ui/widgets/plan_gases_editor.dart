/// Editor for the plan's gas list. Each row exposes the gas label + a
/// diluent toggle + delete. Reordering is intentionally absent: gas
/// index stability is critical (segments reference by index).
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('GASES', style: AppTypography.label),
        for (var i = 0; i < gases.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 100,
                  child: Text(_label(gases[i]), style: AppTypography.readoutSm),
                ),
                Expanded(
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Diluent', style: AppTypography.caption),
                    value: gases[i].isDiluent,
                    onChanged: (v) => onReplace(
                      i,
                      DivePlanGas(
                        oxygenPercent: gases[i].oxygenPercent,
                        heliumPercent: gases[i].heliumPercent,
                        isDiluent: v,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onRemove(i),
                ),
              ],
            ),
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

  static String _label(DivePlanGas g) {
    if (g.heliumPercent > 0) {
      return 'Tx${g.oxygenPercent}/${g.heliumPercent}';
    }
    if (g.oxygenPercent == 21) return 'Air';
    return 'EAN${g.oxygenPercent}';
  }
}
