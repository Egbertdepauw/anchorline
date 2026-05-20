/// Editor for the plan's segment list. Each row exposes depth / duration
/// / gas / setpoint as inline-editable controls. Time = 0 means the row
/// is an instantaneous gas-or-setpoint switch (no actual dive time).
library;

import 'package:flutter/material.dart';

import '../../data/models/dive_plan.dart';
import '../theme/tokens.dart';
import 'gas_safety_readout.dart';

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

  static String gasLabel(DivePlanGas g) {
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
          _SegmentRow(
            // Key ties the State to the segment slot, not the value —
            // editing depth doesn't blow away the row's controllers.
            key: ValueKey('seg-$i'),
            index: i,
            segment: segments[i],
            gases: gases,
            mode: mode,
            onReplace: onReplace,
            onRemove: onRemove,
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

/// One row of the segments editor. Stateful so the depth / time
/// TextEditingControllers persist across parent rebuilds while the
/// user is typing.
class _SegmentRow extends StatefulWidget {
  const _SegmentRow({
    super.key,
    required this.index,
    required this.segment,
    required this.gases,
    required this.mode,
    required this.onReplace,
    required this.onRemove,
  });

  final int index;
  final DivePlanSegment segment;
  final List<DivePlanGas> gases;
  final DivePlanMode mode;
  final void Function(int idx, DivePlanSegment s) onReplace;
  final ValueChanged<int> onRemove;

  @override
  State<_SegmentRow> createState() => _SegmentRowState();
}

class _SegmentRowState extends State<_SegmentRow> {
  late final TextEditingController _depthCtrl;
  late final TextEditingController _timeCtrl;
  final FocusNode _depthFocus = FocusNode();
  final FocusNode _timeFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _depthCtrl = TextEditingController(
      text: widget.segment.depthMeters.toStringAsFixed(0),
    );
    _timeCtrl = TextEditingController(
      text: '${widget.segment.durationMinutes}',
    );
  }

  @override
  void didUpdateWidget(_SegmentRow old) {
    super.didUpdateWidget(old);
    // External update (e.g. saved plan loaded) — sync controller text
    // unless the user is currently editing the field.
    final newDepthText = widget.segment.depthMeters.toStringAsFixed(0);
    if (!_depthFocus.hasFocus && _depthCtrl.text != newDepthText) {
      _depthCtrl.text = newDepthText;
    }
    final newTimeText = '${widget.segment.durationMinutes}';
    if (!_timeFocus.hasFocus && _timeCtrl.text != newTimeText) {
      _timeCtrl.text = newTimeText;
    }
  }

  @override
  void dispose() {
    _depthCtrl.dispose();
    _timeCtrl.dispose();
    _depthFocus.dispose();
    _timeFocus.dispose();
    super.dispose();
  }

  void _emit({
    double? depthMeters,
    int? durationMinutes,
    int? gasMixIndex,
    double? setpoint,
    bool clearSetpoint = false,
  }) {
    widget.onReplace(
      widget.index,
      DivePlanSegment(
        depthMeters: depthMeters ?? widget.segment.depthMeters,
        durationMinutes: durationMinutes ?? widget.segment.durationMinutes,
        gasMixIndex: gasMixIndex ?? widget.segment.gasMixIndex,
        setpoint: clearSetpoint ? null : (setpoint ?? widget.segment.setpoint),
      ),
    );
  }

  /// Snap an externally-stored setpoint to the closest dropdown value.
  /// Dropdowns reject `value` arguments that aren't in their item list.
  double? _normalisedSp(double? sp) {
    if (sp == null) return null;
    const allowed = [0.5, 0.7, 1.0, 1.2, 1.3, 1.4];
    var best = allowed.first;
    var bestDelta = (sp - best).abs();
    for (final v in allowed) {
      final d = (sp - v).abs();
      if (d < bestDelta) {
        best = v;
        bestDelta = d;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    // Per-segment safety readout: evaluate the chosen gas at THIS row's
    // depth. The dropdown below filters by [isGasSelectableAt] (PPO₂
    // hard-cap 1.61) so the diver can't pick a worse one — but the
    // currently-stored selection may already be unsafe (e.g. depth was
    // edited after the gas was picked), so we keep it pickable in the
    // dropdown items and let the warning line flag it.
    final segDepth = widget.segment.depthMeters;
    final selectedGas =
        widget.segment.gasMixIndex < widget.gases.length
            ? widget.gases[widget.segment.gasMixIndex]
            : null;
    final safety = selectedGas == null
        ? null
        : computeGasSafetyReadout(selectedGas, segDepth);

    // Items: only safe-at-this-depth gases, except always include the
    // currently-selected one so DropdownButton doesn't assert.
    final items = <DropdownMenuItem<int>>[];
    for (var gi = 0; gi < widget.gases.length; gi++) {
      final isSafe = isGasSelectableAt(widget.gases[gi], segDepth);
      final isSelected = gi == widget.segment.gasMixIndex;
      if (!isSafe && !isSelected) continue;
      items.add(
        DropdownMenuItem(
          value: gi,
          child: Text(
            PlanSegmentsEditor.gasLabel(widget.gases[gi]),
            style: AppTypography.readoutSm.copyWith(
              color: isSafe ? null : const Color(0xFFE74C3C),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 72,
                child: TextField(
                  controller: _depthCtrl,
                  focusNode: _depthFocus,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    isDense: true,
                    suffixText: 'm',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  ),
                  onChanged: (s) {
                    final v = double.tryParse(s);
                    if (v != null) _emit(depthMeters: v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 88,
                child: TextField(
                  controller: _timeCtrl,
                  focusNode: _timeFocus,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    suffixText: 'min',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  ),
                  onChanged: (s) {
                    final v = int.tryParse(s);
                    if (v != null) _emit(durationMinutes: v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<int>(
                  value: widget.segment.gasMixIndex < widget.gases.length
                      ? widget.segment.gasMixIndex
                      : null,
                  isDense: true,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  hint: const Text('Gas'),
                  items: items,
                  onChanged: (v) {
                    if (v != null) _emit(gasMixIndex: v);
                  },
                ),
              ),
              if (widget.mode == DivePlanMode.cc)
                SizedBox(
                  width: 64,
                  child: DropdownButton<double?>(
                    value: _normalisedSp(widget.segment.setpoint),
                    isDense: true,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('—')),
                      DropdownMenuItem(value: 0.5, child: Text('0.5')),
                      DropdownMenuItem(value: 0.7, child: Text('0.7')),
                      DropdownMenuItem(value: 1.0, child: Text('1.0')),
                      DropdownMenuItem(value: 1.2, child: Text('1.2')),
                      DropdownMenuItem(value: 1.3, child: Text('1.3')),
                      DropdownMenuItem(value: 1.4, child: Text('1.4')),
                    ],
                    onChanged: (v) {
                      if (v == null) {
                        _emit(clearSetpoint: true);
                      } else {
                        _emit(setpoint: v);
                      }
                    },
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => widget.onRemove(widget.index),
              ),
            ],
          ),
          // Per-segment safety line — only when the chosen gas reports
          // a warning or hard-unsafe state at THIS segment's depth.
          // Green / neutral states are silent here to keep the editor
          // uncluttered; the gas editor's status line carries those.
          if (safety != null && (safety.isUnsafe || safety.isWarning))
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
