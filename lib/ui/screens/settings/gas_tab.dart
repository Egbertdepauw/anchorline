import 'package:flutter/material.dart';

import '../../../analyzer/transport/analyzer_transport_options.dart'
    show analyzerBridgeAvailable;
import '../../../labels/label_print_service.dart';
import '../../components/setting_row.dart';
import '../../notifiers/settings_notifier.dart';
import '../../theme/tokens.dart';
import '../../widgets/analyzer_bridge_settings_section.dart';
import '../../widgets/label_printer_settings_section.dart';
import 'settings_fields.dart';

/// Gas: blending, the analyzer and the label printer, in the order of the Gas
/// destination's tabs.
class GasSettingsTab extends StatelessWidget {
  const GasSettingsTab({
    super.key,
    required this.notifier,
    this.labelPrinting,
  });

  final SettingsNotifier notifier;
  final LabelPrintService? labelPrinting;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: notifier,
      builder: (context, _) => ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          SettingsGroup(
            title: 'Blending prices',
            children: [
              SettingRow(
                title: 'Oxygen',
                control: SettingTextField(
                  key: const ValueKey('settings-blend-o2-cost'),
                  initialValue:
                      notifier.blendOxygenCostPerLitre.toStringAsFixed(3),
                  suffix: '/ L',
                  keyboardType: decimalKeyboard,
                  onChanged: (s) {
                    final v = double.tryParse(s);
                    if (v != null) notifier.setBlendOxygenCostPerLitre(v);
                  },
                ),
              ),
              SettingRow(
                title: 'Helium',
                control: SettingTextField(
                  key: const ValueKey('settings-blend-he-cost'),
                  initialValue:
                      notifier.blendHeliumCostPerLitre.toStringAsFixed(3),
                  suffix: '/ L',
                  keyboardType: decimalKeyboard,
                  onChanged: (s) {
                    final v = double.tryParse(s);
                    if (v != null) notifier.setBlendHeliumCostPerLitre(v);
                  },
                ),
              ),
              SettingRow(
                title: 'Top-off fill fee',
                helper: 'Air or nitrox, per fill',
                control: SettingTextField(
                  key: const ValueKey('settings-blend-air-fee'),
                  initialValue: notifier.blendAirFlatFee.toStringAsFixed(2),
                  keyboardType: decimalKeyboard,
                  onChanged: (s) {
                    final v = double.tryParse(s);
                    if (v != null) notifier.setBlendAirFlatFee(v);
                  },
                ),
              ),
            ],
          ),
          SettingsGroup(
            title: 'Blend tab starts with',
            children: [
              SettingRow(
                title: 'Top-off gas',
                control: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SettingTextField(
                      key: const ValueKey('settings-blend-topoff-o2'),
                      initialValue: '${notifier.blendTopoffOxygenPercent}',
                      suffix: '%',
                      width: 72,
                      keyboardType: TextInputType.number,
                      onChanged: (s) {
                        final v = int.tryParse(s);
                        if (v != null) {
                          notifier.setBlendTopoff(
                              v, notifier.blendTopoffHeliumPercent);
                        }
                      },
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: Spacing.xs),
                      child: Text('/'),
                    ),
                    SettingTextField(
                      key: const ValueKey('settings-blend-topoff-he'),
                      initialValue: '${notifier.blendTopoffHeliumPercent}',
                      suffix: '%',
                      width: 72,
                      keyboardType: TextInputType.number,
                      onChanged: (s) {
                        final v = int.tryParse(s);
                        if (v != null) {
                          notifier.setBlendTopoff(
                              notifier.blendTopoffOxygenPercent, v);
                        }
                      },
                    ),
                  ],
                ),
              ),
              SettingRow(
                title: 'Fill order',
                // Capped and expanded, so the label ellipsizes rather than
                // overflowing on a narrow phone or at large text.
                control: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 170),
                  child: DropdownButton<String>(
                    key: const ValueKey('settings-blend-sequence'),
                    value: notifier.blendFillSequence,
                    isDense: true,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: 'heThenO2ThenTopoff',
                        child: _OrderLabel('He → O₂ → top-off'),
                      ),
                      DropdownMenuItem(
                        value: 'o2ThenHeThenTopoff',
                        child: _OrderLabel('O₂ → He → top-off'),
                      ),
                      DropdownMenuItem(
                        value: 'o2ThenTopoffThenHe',
                        child: _OrderLabel('O₂ → top-off → He'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) notifier.setBlendFillSequence(v);
                    },
                  ),
                ),
              ),
              SettingRow(
                title: 'Real-gas maths (Z)',
                helper: 'Off: ideal gas',
                onTap: () =>
                    notifier.setBlendUseRealGas(!notifier.blendUseRealGas),
                control: Switch(
                  key: const ValueKey('settings-blend-real-gas'),
                  value: notifier.blendUseRealGas,
                  onChanged: notifier.setBlendUseRealGas,
                ),
              ),
              SettingRow(
                title: 'Fill / settled temp',
                control: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SettingTextField(
                      key: const ValueKey('settings-blend-fill-temp'),
                      initialValue: notifier.blendFillTempC.toStringAsFixed(0),
                      suffix: '°C',
                      width: 76,
                      keyboardType: decimalKeyboard,
                      onChanged: (s) {
                        final v = double.tryParse(s);
                        if (v != null) notifier.setBlendFillTempC(v);
                      },
                    ),
                    const SizedBox(width: Spacing.sm),
                    SettingTextField(
                      key: const ValueKey('settings-blend-settled-temp'),
                      initialValue:
                          notifier.blendSettledTempC.toStringAsFixed(0),
                      suffix: '°C',
                      width: 76,
                      keyboardType: decimalKeyboard,
                      onChanged: (s) {
                        final v = double.tryParse(s);
                        if (v != null) notifier.setBlendSettledTempC(v);
                      },
                    ),
                  ],
                ),
              ),
              SettingRow(
                title: 'Settle time (min)',
                control: SettingTextField(
                  key: const ValueKey('settings-blend-settle-minutes'),
                  initialValue: notifier.blendSettleMinutes.toString(),
                  width: 76,
                  keyboardType: TextInputType.number,
                  onChanged: (s) {
                    final v = int.tryParse(s);
                    if (v != null) notifier.setBlendSettleMinutes(v);
                  },
                ),
              ),
              SettingRow(
                title: 'Diluent cylinder up to (L)',
                control: SettingTextField(
                  key: const ValueKey('settings-blend-diluent-max-l'),
                  initialValue: _bar(notifier.blendDiluentMaxL),
                  suffix: 'L',
                  width: 76,
                  keyboardType: decimalKeyboard,
                  onChanged: (s) {
                    final v = double.tryParse(s);
                    if (v != null) notifier.setBlendDiluentMaxL(v);
                  },
                ),
              ),
            ],
          ),
          SettingsGroup(
            title: 'Analyzer',
            children: [
              SettingBlock(
                title: 'MOD rows at ppO₂',
                child: _ModChips(notifier: notifier),
              ),
              SettingRow(
                title: 'Fill pressure starts at',
                control: SettingTextField(
                  key: const ValueKey('settings-fill-pressure-start'),
                  initialValue: _bar(notifier.analyzerFillPressureStartBar),
                  suffix: 'bar',
                  width: 104,
                  keyboardType: decimalKeyboard,
                  onChanged: (s) {
                    final v = double.tryParse(s);
                    if (v != null) notifier.setAnalyzerFillPressureStartBar(v);
                  },
                ),
              ),
            ],
          ),
          if (labelPrinting != null)
            SettingsGroup(
              title: 'Label printer',
              children: [
                LabelPrinterSettingsSection(
                  settings: notifier,
                  printing: labelPrinting!,
                ),
              ],
            ),
          if (analyzerBridgeAvailable)
            SettingsGroup(
              title: 'Analyzer bridge',
              children: [
                AnalyzerBridgeSettingsSection(settings: notifier),
              ],
            ),
        ],
      ),
    );
  }

  static String _bar(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
}

class _OrderLabel extends StatelessWidget {
  const _OrderLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
}

/// The MOD ppO₂ limits as chips with a ✕ each (none on the last one left),
/// and a "+ Add" chip that opens a dialog.
class _ModChips extends StatelessWidget {
  const _ModChips({required this.notifier});

  final SettingsNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final limits = notifier.analyzerModPpo2s;
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      children: [
        for (final p in limits)
          Container(
            key: ValueKey('settings-mod-ppo2-$p'),
            constraints: const BoxConstraints(minHeight: 36),
            padding: EdgeInsets.only(
                left: Spacing.md, right: limits.length > 1 ? 0 : Spacing.md),
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              borderRadius: Radii.chipBr,
              border: Border.all(color: palette.surfaceBezel),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$p',
                    style: AppTypography.readoutMd
                        .copyWith(color: palette.textPrimary, fontSize: 13)),
                if (limits.length > 1)
                  InkResponse(
                    key: ValueKey('settings-mod-ppo2-$p-remove'),
                    // Read the list at tap time, not from this build: two
                    // quick taps must both land.
                    onTap: () => notifier.setAnalyzerModPpo2s(
                        notifier.analyzerModPpo2s.where((l) => l != p)),
                    radius: 22,
                    // 44 pt hit area; the chip stays 36 pt high and the
                    // target overhangs it vertically.
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(Icons.close,
                          size: 14, color: palette.textMuted),
                    ),
                  ),
              ],
            ),
          ),
        InkWell(
          key: const ValueKey('settings-mod-ppo2-add'),
          onTap: () => _add(context),
          borderRadius: Radii.chipBr,
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              borderRadius: Radii.chipBr,
              border: Border.all(color: palette.surfaceBezel),
            ),
            child: Text('+ Add',
                style: AppTypography.body.copyWith(
                    color: palette.accentPrimary,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Future<void> _add(BuildContext context) async {
    final value = await showDialog<double>(
      context: context,
      builder: (_) => const _AddModDialog(),
    );
    if (value != null) {
      await notifier
          .setAnalyzerModPpo2s([...notifier.analyzerModPpo2s, value]);
    }
  }
}

class _AddModDialog extends StatefulWidget {
  const _AddModDialog();

  @override
  State<_AddModDialog> createState() => _AddModDialogState();
}

class _AddModDialogState extends State<_AddModDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.trim().replaceAll(',', '.'));
    const min = SettingsNotifier.analyzerModPpo2Min;
    const max = SettingsNotifier.analyzerModPpo2Max;
    final rounded = v == null ? null : (v * 100).round() / 100;
    if (rounded == null || rounded < min || rounded > max) {
      setState(() => _error =
          'Enter a ppO₂ from ${min.toStringAsFixed(1)} to ${max.toStringAsFixed(1)}');
      return;
    }
    Navigator.of(context).pop(rounded);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add MOD limit'),
      content: TextField(
        key: const ValueKey('settings-mod-ppo2-input'),
        controller: _ctrl,
        autofocus: true,
        keyboardType: decimalKeyboard,
        decoration: InputDecoration(
          labelText: 'ppO₂ (bar)',
          hintText: '1.6',
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('settings-mod-ppo2-add-confirm'),
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
