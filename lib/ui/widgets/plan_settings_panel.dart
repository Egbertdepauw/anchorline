/// Collapsible plan-level settings panel. Shows resolved values
/// (defaults + overrides) as separate Text widgets in a summary row;
/// expand to override individual settings.
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
  });

  final SettingsNotifier settings;
  final DivePlanSettings overrides;
  final ValueChanged<DivePlanSettings> onChange;

  @override
  State<PlanSettingsPanel> createState() => _PlanSettingsPanelState();
}

class _PlanSettingsPanelState extends State<PlanSettingsPanel> {
  bool _expanded = false;

  int get _gfLow =>
      widget.overrides.gfLow ?? widget.settings.plannerGfLow;
  int get _gfHigh =>
      widget.overrides.gfHigh ?? widget.settings.plannerGfHigh;
  double get _bottomSp =>
      widget.overrides.bottomSetpoint ?? widget.settings.plannerBottomSetpoint;
  double get _ascentSp =>
      widget.overrides.ascentSetpoint ?? widget.settings.plannerAscentSetpoint;
  double get _decoSp =>
      widget.overrides.decoSetpoint ?? widget.settings.plannerDecoSetpoint;
  double get _lastStop =>
      widget.overrides.lastStopDepthMeters ??
      widget.settings.plannerLastStopDepthMeters;

  String _algoLabel() =>
      widget.overrides.useVpmb ?? widget.settings.plannerUseVpmb
          ? 'VPM-B+${widget.overrides.vpmbConservatism ?? widget.settings.plannerVpmbConservatism}'
          : '$_gfLow/$_gfHigh';

  String _setpointsLabel() =>
      '${_bottomSp.toStringAsFixed(1)} / ${_ascentSp.toStringAsFixed(1)} / ${_decoSp.toStringAsFixed(1)}';

  String _lastStopLabel() => '${_lastStop.toStringAsFixed(0)} m';

  @override
  Widget build(BuildContext context) {
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
                      Text(_algoLabel(), style: AppTypography.caption),
                      const Text('·', style: AppTypography.caption),
                      Text(_setpointsLabel(), style: AppTypography.caption),
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
                Row(children: [
                  const SizedBox(width: 100, child: Text('GF Low')),
                  Expanded(
                      child: _intField(
                          value: _gfLow,
                          onChanged: (v) => widget.onChange(
                              widget.overrides.copyWith(gfLow: v)))),
                ]),
                Row(children: [
                  const SizedBox(width: 100, child: Text('GF High')),
                  Expanded(
                      child: _intField(
                          value: _gfHigh,
                          onChanged: (v) => widget.onChange(
                              widget.overrides.copyWith(gfHigh: v)))),
                ]),
                Row(children: [
                  const SizedBox(width: 100, child: Text('Bottom SP')),
                  Expanded(
                      child: _doubleField(
                          value: _bottomSp,
                          onChanged: (v) => widget.onChange(
                              widget.overrides.copyWith(bottomSetpoint: v)))),
                ]),
                Row(children: [
                  const SizedBox(width: 100, child: Text('Ascent SP')),
                  Expanded(
                      child: _doubleField(
                          value: _ascentSp,
                          onChanged: (v) => widget.onChange(
                              widget.overrides.copyWith(ascentSetpoint: v)))),
                ]),
                Row(children: [
                  const SizedBox(width: 100, child: Text('Deco SP')),
                  Expanded(
                      child: _doubleField(
                          value: _decoSp,
                          onChanged: (v) => widget.onChange(
                              widget.overrides.copyWith(decoSetpoint: v)))),
                ]),
                Row(children: [
                  const SizedBox(width: 100, child: Text('Last stop')),
                  Expanded(
                      child: _doubleField(
                          value: _lastStop,
                          onChanged: (v) => widget.onChange(widget.overrides
                              .copyWith(lastStopDepthMeters: v)))),
                ]),
              ],
            ),
          ),
      ],
    );
  }

  Widget _intField(
          {required int value, required ValueChanged<int> onChanged}) =>
      TextFormField(
        initialValue: '$value',
        keyboardType: TextInputType.number,
        onChanged: (s) {
          final v = int.tryParse(s);
          if (v != null) onChanged(v);
        },
      );

  Widget _doubleField(
          {required double value,
          required ValueChanged<double> onChanged}) =>
      TextFormField(
        initialValue: value.toStringAsFixed(1),
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        onChanged: (s) {
          final v = double.tryParse(s);
          if (v != null) onChanged(v);
        },
      );
}
