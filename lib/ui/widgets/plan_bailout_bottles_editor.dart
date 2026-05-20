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
  });

  final List<DivePlanGas> gases;
  final List<DivePlanBailoutBottle> bottles;
  final ValueChanged<DivePlanBailoutBottle> onAdd;
  final ValueChanged<int> onRemove;

  static String _gasLabel(DivePlanGas g) {
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
        for (var i = 0; i < bottles.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                    child: Text(
                        '${_gasLabel(gases[bottles[i].gasMixIndex])} · '
                        '${bottles[i].waterCapacityL.toStringAsFixed(1)} L · '
                        '${bottles[i].fillPressureBar} bar')),
                IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => onRemove(i)),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('add-bottle'),
            icon: const Icon(Icons.add),
            label: const Text('Add bailout bottle'),
            onPressed: () => onAdd(const DivePlanBailoutBottle(
                gasMixIndex: 0, waterCapacityL: 5.7, fillPressureBar: 200)),
          ),
        ),
      ],
    );
  }
}
