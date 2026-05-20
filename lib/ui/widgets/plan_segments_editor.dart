/// Editor for the plan's segment list. Each row shows depth / duration /
/// gas label / setpoint (CC only) + a delete button. Inline field editing
/// is deferred to Task 17; this widget handles display + add/remove.
library;

import 'package:flutter/material.dart';

import '../../data/models/dive_plan.dart';
import '../theme/tokens.dart';

class PlanSegmentsEditor extends StatelessWidget {
  const PlanSegmentsEditor({
    super.key,
    required this.gases,
    required this.segments,
    required this.onAdd,
    required this.onRemove,
    required this.onReplace,
    required this.onReorder,
    required this.mode,
  });

  final List<DivePlanGas> gases;
  final List<DivePlanSegment> segments;
  final ValueChanged<DivePlanSegment> onAdd;
  final ValueChanged<int> onRemove;
  final void Function(int idx, DivePlanSegment s) onReplace;
  final void Function(int oldIdx, int newIdx) onReorder;
  final DivePlanMode mode;

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
        Text('SEGMENTS', style: AppTypography.label),
        for (var i = 0; i < segments.length; i++)
          Padding(
            key: ValueKey('seg-$i'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 60,
                  child: Text(
                    '${segments[i].depthMeters.toStringAsFixed(0)} m',
                    style: AppTypography.readoutSm,
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: Text(
                    '${segments[i].durationMinutes} min',
                    style: AppTypography.readoutSm,
                  ),
                ),
                Expanded(
                  child: Text(
                    _gasLabel(gases[segments[i].gasMixIndex]),
                    style: AppTypography.readoutSm,
                  ),
                ),
                if (mode == DivePlanMode.cc)
                  SizedBox(
                    width: 50,
                    child: Text(
                      segments[i].setpoint == null
                          ? '—'
                          : segments[i].setpoint!.toStringAsFixed(1),
                      style: AppTypography.readoutSm,
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
            key: const ValueKey('add-segment'),
            icon: const Icon(Icons.add),
            label: const Text('Add segment'),
            onPressed: () {
              double depth = 10;
              if (segments.isNotEmpty) {
                final deepest = segments
                    .map((s) => s.depthMeters)
                    .reduce((a, b) => a > b ? a : b);
                depth = deepest + 10;
              }
              onAdd(DivePlanSegment(
                depthMeters: depth,
                durationMinutes: 10,
                gasMixIndex: 0,
                setpoint: mode == DivePlanMode.cc ? 1.3 : null,
              ));
            },
          ),
        ),
      ],
    );
  }
}
