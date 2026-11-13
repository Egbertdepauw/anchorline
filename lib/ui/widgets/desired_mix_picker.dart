/// Tap-to-pick chips for the desired mix of a cylinder (issue #114).
///
/// Used by the analyzer's save card and by the analysis log's edit dialog.
/// The caller decides which mixes to offer (the targets of the open
/// blends, then the recent desired mixes of the log); "Other…" asks for any other mix.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/gas_analysis.dart';
import '../theme/tokens.dart';

/// One chip per mix in [options], then "Other…". Tapping a chip selects its
/// mix and tapping the selected chip again clears the choice (`onChanged`
/// gets null), because the desired mix is optional.
///
/// [options] must not hold the same mix twice. A [selected] mix that is not
/// in [options], because it was typed in through "Other…", gets a chip of
/// its own after the options.
///
/// [dense] chips are 32 pt high, the floor for chips, with no padding around
/// them for a larger tap target (the Analyse tab's height budget).
class DesiredMixPicker extends StatelessWidget {
  const DesiredMixPicker({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.dense = false,
  });

  final List<DesiredMix> options;
  final DesiredMix? selected;
  final ValueChanged<DesiredMix?> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final current = selected;
    final tapTarget = dense ? MaterialTapTargetSize.shrinkWrap : null;
    // One step down from the standard density takes the chip from 34 to the
    // 32 pt floor, on every platform.
    final density = dense ? const VisualDensity(vertical: -1) : null;
    return Wrap(
      spacing: dense ? 6 : Spacing.sm,
      runSpacing: dense ? 6 : Spacing.sm,
      children: [
        for (final mix in [
          ...options,
          if (current != null && !options.contains(current)) current,
        ])
          ChoiceChip(
            key: ValueKey('desired-mix-${mix.o2Percent}-${mix.hePercent}'),
            label: Text(mix.name),
            selected: mix == current,
            materialTapTargetSize: tapTarget,
            visualDensity: density,
            onSelected: (_) => onChanged(mix == current ? null : mix),
          ),
        ActionChip(
          key: const ValueKey('desired-mix-other'),
          label: const Text('Other…'),
          materialTapTargetSize: tapTarget,
          visualDensity: density,
          onPressed: () => _pickOther(context),
        ),
      ],
    );
  }

  Future<void> _pickOther(BuildContext context) async {
    final picked = await showOtherMixDialog(context);
    if (picked != null && context.mounted) onChanged(picked);
  }
}

/// Asks for any mix as whole O2 / He percents; null when cancelled. Shared
/// by the picker's "Other…" chip and the Blend tab's top-off "Other…".
Future<DesiredMix?> showOtherMixDialog(BuildContext context) =>
    showDialog<DesiredMix>(
      context: context,
      builder: (_) => const _OtherMixDialog(),
    );

/// O2 and He as whole percents. OK checks them and, if they are not a
/// breathable mix, shows what is wrong instead of closing. After the first
/// try the errors follow what the user types.
class _OtherMixDialog extends StatefulWidget {
  const _OtherMixDialog();

  @override
  State<_OtherMixDialog> createState() => _OtherMixDialogState();
}

class _OtherMixDialogState extends State<_OtherMixDialog> {
  final _o2 = TextEditingController();
  final _he = TextEditingController(text: '0');
  bool _tried = false;

  @override
  void dispose() {
    _o2.dispose();
    _he.dispose();
    super.dispose();
  }

  /// The typed values and what is wrong with them. An emptied He is 0.
  ({int? o2, int? he, String? o2Error, String? heError}) _check() {
    final o2 = int.tryParse(_o2.text);
    final he = _he.text.isEmpty ? 0 : int.tryParse(_he.text);
    final o2Error =
        o2 == null || o2 < 1 || o2 > 100 ? 'O2 must be 1–100 %' : null;
    final heError = he == null || he < 0 || he > 99
        ? 'He must be 0–99 %'
        : o2Error == null && o2! + he > 100
            ? "O2 + He can't exceed 100 %"
            : null;
    return (o2: o2, he: he, o2Error: o2Error, heError: heError);
  }

  void _submit() {
    final c = _check();
    if (c.o2Error != null || c.heError != null) {
      setState(() => _tried = true);
      return;
    }
    Navigator.of(context).pop(DesiredMix(c.o2!, c.he!));
  }

  @override
  Widget build(BuildContext context) {
    final c = _check();
    return AlertDialog(
      title: const Text('Other mix'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('desired-mix-other-o2'),
            controller: _o2,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: _digits,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'O2 %',
              errorText: _tried ? c.o2Error : null,
              errorMaxLines: 2,
            ),
          ),
          const SizedBox(height: Spacing.md),
          TextField(
            key: const ValueKey('desired-mix-other-he'),
            controller: _he,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: _digits,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'He %',
              errorText: _tried ? c.heError : null,
              errorMaxLines: 2,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('desired-mix-other-ok'),
          onPressed: _submit,
          child: const Text('OK'),
        ),
      ],
    );
  }
}

final List<TextInputFormatter> _digits = [
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(3),
];
