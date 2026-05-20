/// Editor for the plan's gas list. Each row exposes O₂ / He as
/// numeric inputs plus a delete button. Reordering is intentionally
/// absent — gas index stability is critical (segments reference by
/// index).
///
/// The model's `isDiluent` flag is no longer exposed in this editor.
/// In CC mode the deco planner ignores all gases except the one active
/// at the last segment (no auto-switching), so a per-gas diluent flag
/// added nothing but confusion. The field is kept on [DivePlanGas]
/// because other analysis surfaces (profile chart legend, ICD checks,
/// crosshair tooltip) read it from imported / live dives — but new
/// gases added through this editor are always saved with
/// `isDiluent: true`.
library;

import 'package:flutter/material.dart';

import '../../data/models/dive_plan.dart';
import '../theme/tokens.dart';
import 'gas_safety_readout.dart';

class PlanGasesEditor extends StatelessWidget {
  const PlanGasesEditor({
    super.key,
    required this.gases,
    required this.onAdd,
    required this.onRemove,
    required this.onReplace,
    this.segments = const [],
  });

  final List<DivePlanGas> gases;
  final ValueChanged<DivePlanGas> onAdd;
  final ValueChanged<int> onRemove;
  final void Function(int idx, DivePlanGas g) onReplace;

  /// Planned segments — used to compute per-gas safety: the deepest
  /// depth at which each gas is the active gas, so the editor can
  /// surface MOD violations / high PPO2 / high END inline.
  final List<DivePlanSegment> segments;

  static String mixLabel(DivePlanGas g) {
    if (g.heliumPercent > 0) {
      return 'Tx${g.oxygenPercent}/${g.heliumPercent}';
    }
    if (g.oxygenPercent == 21) return 'Air';
    return 'EAN${g.oxygenPercent}';
  }

  /// Deepest planned depth (m) at which gas index [gasIndex] is the
  /// active gas. Returns null when the gas is never used as the active
  /// gas in any time>0 segment.
  static double? deepestDepthForGas(
      List<DivePlanSegment> segments, int gasIndex) {
    double? deepest;
    for (final s in segments) {
      if (s.gasMixIndex != gasIndex) continue;
      if (s.durationMinutes <= 0) continue;
      if (deepest == null || s.depthMeters > deepest) {
        deepest = s.depthMeters;
      }
    }
    return deepest;
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
            usageDeepestDepth: deepestDepthForGas(segments, i),
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
    this.usageDeepestDepth,
  });

  final int index;
  final DivePlanGas gas;
  final void Function(int idx, DivePlanGas g) onReplace;
  final ValueChanged<int> onRemove;

  /// Deepest planned segment depth at which this gas is active. Drives
  /// the inline safety chip (MOD / END / PPO2 / unusable-warning).
  final double? usageDeepestDepth;

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

  void _emit({int? o2, int? he}) {
    widget.onReplace(
      widget.index,
      DivePlanGas(
        oxygenPercent: (o2 ?? widget.gas.oxygenPercent).clamp(1, 100),
        heliumPercent: (he ?? widget.gas.heliumPercent).clamp(0, 99),
        isDiluent: widget.gas.isDiluent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final safety =
        computeGasSafetyReadout(widget.gas, widget.usageDeepestDepth);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => widget.onRemove(widget.index),
              ),
            ],
          ),
          if (safety != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 4),
              child: Text(
                safety.text,
                style: AppTypography.caption.copyWith(color: safety.color),
              ),
            ),
        ],
      ),
    );
  }
}

// Per-row safety colouring is now driven by the shared
// [computeGasSafetyReadout] in gas_safety_readout.dart so the segments
// editor uses the same thresholds (green ≤ 1.1, amber to 1.51, red
// above). The local helper that lived here has been retired.
