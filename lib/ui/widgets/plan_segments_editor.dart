/// Editor for the plan's segment list. Each row exposes depth / duration
/// / gas / setpoint as inline-editable controls. Time = 0 means the row
/// is an instantaneous gas-or-setpoint switch (no actual dive time).
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: TextField(
              controller: _depthCtrl,
              focusNode: _depthFocus,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                isDense: true,
                suffixText: 'm',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              ),
              onChanged: (s) {
                final v = double.tryParse(s);
                if (v != null) _emit(depthMeters: v);
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: TextField(
              controller: _timeCtrl,
              focusNode: _timeFocus,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                suffixText: 'min',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 4, vertical: 6),
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
              items: [
                for (var gi = 0; gi < widget.gases.length; gi++)
                  DropdownMenuItem(
                    value: gi,
                    child: Text(
                      PlanSegmentsEditor.gasLabel(widget.gases[gi]),
                      style: AppTypography.readoutSm,
                    ),
                  ),
              ],
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
    );
  }
}
