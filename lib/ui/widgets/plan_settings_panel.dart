/// Collapsible plan-level settings panel.
///
/// Header: a single-line summary of the resolved values (defaults +
/// overrides). The diver sees their algorithm + setpoints + last-stop
/// without having to expand. Expanding reveals overrides for every
/// field plus the CC/OC mode toggle and the algorithm picker
/// (ZHL-16C + GF vs VPM-B + conservatism).
///
/// VPM-B forward planning isn't implemented yet — the toggle accepts
/// the diver's intent and stamps the plan so when the planner gains
/// a forward VPM-B engine the existing saved plans pick it up
/// automatically. Today the planner falls back to ZHL-16C + GF when
/// VPM-B is selected; the UI notes this inline.
library;

import 'package:flutter/material.dart';

import '../../data/models/dive_plan.dart';
import '../notifiers/settings_notifier.dart';
import '../theme/tokens.dart';

class PlanSettingsPanel extends StatefulWidget {
  const PlanSettingsPanel({
    super.key,
    required this.settings,
    required this.overrides,
    required this.onChange,
    this.mode = DivePlanMode.cc,
    this.onModeChange,
  });

  final SettingsNotifier settings;
  final DivePlanSettings overrides;
  final ValueChanged<DivePlanSettings> onChange;

  /// Current plan mode. Driven by the notifier, not the overrides
  /// (mode lives on the plan itself, not the settings record).
  final DivePlanMode mode;

  /// Called when the diver toggles CC ⇄ OC. Optional — when omitted
  /// the segmented control is rendered disabled (read-only view).
  final ValueChanged<DivePlanMode>? onModeChange;

  @override
  State<PlanSettingsPanel> createState() => _PlanSettingsPanelState();
}

class _PlanSettingsPanelState extends State<PlanSettingsPanel> {
  bool _expanded = false;

  int get _gfLow =>
      widget.overrides.gfLow ?? widget.settings.plannerGfLow;
  int get _gfHigh =>
      widget.overrides.gfHigh ?? widget.settings.plannerGfHigh;
  bool get _useVpmb =>
      widget.overrides.useVpmb ?? widget.settings.plannerUseVpmb;
  int get _vpmbCons =>
      widget.overrides.vpmbConservatism ??
      widget.settings.plannerVpmbConservatism;
  double get _bottomSp =>
      widget.overrides.bottomSetpoint ?? widget.settings.plannerBottomSetpoint;
  double get _ascentSp =>
      widget.overrides.ascentSetpoint ?? widget.settings.plannerAscentSetpoint;
  double get _decoSp =>
      widget.overrides.decoSetpoint ?? widget.settings.plannerDecoSetpoint;
  double get _lastStop =>
      widget.overrides.lastStopDepthMeters ??
      widget.settings.plannerLastStopDepthMeters;
  double get _decoSwitchDepth =>
      widget.overrides.decoSwitchDepthMeters ??
      widget.settings.plannerDecoSwitchDepthMeters;
  int get _ocSac =>
      widget.overrides.ocSac ?? widget.settings.plannerOcSac;

  String _algoLabel() =>
      _useVpmb ? 'VPM-B+$_vpmbCons' : '$_gfLow/$_gfHigh';

  String _modeLabel() => widget.mode == DivePlanMode.cc ? 'CC' : 'OC';

  String _setpointsLabel() =>
      '${_bottomSp.toStringAsFixed(1)} / ${_ascentSp.toStringAsFixed(1)} / ${_decoSp.toStringAsFixed(1)}';

  String _lastStopLabel() => '${_lastStop.toStringAsFixed(0)} m';

  @override
  Widget build(BuildContext context) {
    final isCc = widget.mode == DivePlanMode.cc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const ValueKey('plan-settings-toggle'),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
            child: Row(
              children: [
                Text('SETTINGS', style: AppTypography.label),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    children: [
                      Text(_modeLabel(), style: AppTypography.caption),
                      const Text('·', style: AppTypography.caption),
                      Text(_algoLabel(), style: AppTypography.caption),
                      const Text('·', style: AppTypography.caption),
                      // Setpoints are CC-only — hide on OC plans so the
                      // summary doesn't carry meaningless numbers.
                      if (isCc)
                        Text(_setpointsLabel(), style: AppTypography.caption),
                      if (isCc)
                        const Text('·', style: AppTypography.caption),
                      Text(_lastStopLabel(), style: AppTypography.caption),
                    ],
                  ),
                ),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(
                left: Spacing.sm, bottom: Spacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Mode (CC / OC) ─────────────────────────────────
                _LabeledRow(
                  label: 'Mode',
                  child: SegmentedButton<DivePlanMode>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: DivePlanMode.cc,
                        label: Text('CC'),
                      ),
                      ButtonSegment(
                        value: DivePlanMode.oc,
                        label: Text('OC'),
                      ),
                    ],
                    selected: {widget.mode},
                    onSelectionChanged: widget.onModeChange == null
                        ? null
                        : (s) => widget.onModeChange!(s.first),
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                // ── Algorithm (ZHL-16C + GF / VPM-B) ───────────────
                _LabeledRow(
                  label: 'Algorithm',
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: const [
                      ButtonSegment(value: false, label: Text('ZHL-16C')),
                      ButtonSegment(value: true, label: Text('VPM-B')),
                    ],
                    selected: {_useVpmb},
                    onSelectionChanged: (s) => widget
                        .onChange(widget.overrides.copyWith(useVpmb: s.first)),
                  ),
                ),
                if (_useVpmb)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4, left: 110),
                    child: Text(
                      'VPM-B forward-planning is queued — falls back to '
                      'ZHL-16C + GF until that lands.',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: context.palette.textSecondary,
                      ),
                    ),
                  ),
                const SizedBox(height: Spacing.xs),
                // ── Algorithm parameters (one of two pairs) ────────
                if (_useVpmb)
                  _LabeledRow(
                    label: 'Conservatism',
                    child: _intField(
                      key: const ValueKey('vpmb-conservatism'),
                      value: _vpmbCons,
                      onChanged: (v) => widget.onChange(widget.overrides
                          .copyWith(vpmbConservatism: v.clamp(0, 4))),
                    ),
                  )
                else ...[
                  _LabeledRow(
                    label: 'GF Low',
                    child: _intField(
                      key: const ValueKey('gf-low'),
                      value: _gfLow,
                      onChanged: (v) => widget
                          .onChange(widget.overrides.copyWith(gfLow: v)),
                    ),
                  ),
                  _LabeledRow(
                    label: 'GF High',
                    child: _intField(
                      key: const ValueKey('gf-high'),
                      value: _gfHigh,
                      onChanged: (v) => widget
                          .onChange(widget.overrides.copyWith(gfHigh: v)),
                    ),
                  ),
                ],
                // ── Setpoints (CC only) ────────────────────────────
                if (isCc) ...[
                  _LabeledRow(
                    label: 'Bottom SP',
                    child: _doubleField(
                      value: _bottomSp,
                      onChanged: (v) => widget.onChange(
                          widget.overrides.copyWith(bottomSetpoint: v)),
                    ),
                  ),
                  _LabeledRow(
                    label: 'Ascent SP',
                    child: _doubleField(
                      value: _ascentSp,
                      onChanged: (v) => widget.onChange(
                          widget.overrides.copyWith(ascentSetpoint: v)),
                    ),
                  ),
                  _LabeledRow(
                    label: 'Deco SP',
                    child: _doubleField(
                      value: _decoSp,
                      onChanged: (v) => widget.onChange(
                          widget.overrides.copyWith(decoSetpoint: v)),
                    ),
                  ),
                  _LabeledRow(
                    label: 'Deco SP from',
                    child: _doubleField(
                      key: const ValueKey('deco-sp-switch-depth'),
                      value: _decoSwitchDepth,
                      onChanged: (v) => widget.onChange(widget.overrides
                          .copyWith(decoSwitchDepthMeters: v)),
                      suffix: 'm',
                    ),
                  ),
                ],
                _LabeledRow(
                  label: 'Last stop',
                  child: _doubleField(
                    value: _lastStop,
                    onChanged: (v) => widget.onChange(widget.overrides
                        .copyWith(lastStopDepthMeters: v)),
                    suffix: 'm',
                  ),
                ),
                // ── OC SAC (used in both modes, but only meaningful
                //    on OC plans; CC consumption is metabolic). Surface
                //    it always so the diver can dial it in once. ────
                _LabeledRow(
                  label: 'OC SAC',
                  child: _intField(
                    key: const ValueKey('oc-sac'),
                    value: _ocSac,
                    onChanged: (v) => widget
                        .onChange(widget.overrides.copyWith(ocSac: v)),
                    suffix: 'L/min',
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _intField({
    Key? key,
    required int value,
    required ValueChanged<int> onChanged,
    String? suffix,
  }) =>
      TextFormField(
        key: key,
        initialValue: '$value',
        keyboardType: TextInputType.number,
        decoration:
            suffix == null ? null : InputDecoration(suffixText: suffix),
        onChanged: (s) {
          final v = int.tryParse(s);
          if (v != null) onChanged(v);
        },
      );

  Widget _doubleField({
    Key? key,
    required double value,
    required ValueChanged<double> onChanged,
    String? suffix,
  }) =>
      TextFormField(
        key: key,
        initialValue: value.toStringAsFixed(1),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration:
            suffix == null ? null : InputDecoration(suffixText: suffix),
        onChanged: (s) {
          final v = double.tryParse(s);
          if (v != null) onChanged(v);
        },
      );
}

/// One labelled row in the expanded panel — label on the left, control
/// on the right. Extracted so all rows align vertically without
/// repeating the SizedBox + Row boilerplate everywhere.
class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 100, child: Text(label)),
          Expanded(child: child),
        ],
      ),
    );
  }
}
