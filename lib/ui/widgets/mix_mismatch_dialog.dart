/// The warning before a label is printed for a gas that is not the mix the
/// diver asked for (issue #114).
///
/// Printing is never blocked. On a hard mismatch (see `MixMatchLevel.hard`)
/// the label shows the analysed mix instead of the desired one, and this
/// dialog says so first.
library;

import 'package:flutter/material.dart';

import '../../analysis/gas_naming.dart';
import '../../data/models/gas_analysis.dart';
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';

/// What the diver chose in the mismatch dialog.
enum MismatchChoice { printAnalysed, changeMix, cancel }

/// Asks whether to print [analysis] with its analysed mix on the label.
/// [analysis] must have a desired mix: only a hard mismatch asks, and that
/// needs one. Dismissing the dialog counts as [MismatchChoice.cancel].
Future<MismatchChoice> showMixMismatchDialog(
  BuildContext context, {
  required GasAnalysis analysis,
}) async {
  assert(analysis.desiredMix != null, 'A mismatch needs a desired mix');
  final choice = await showDialog<MismatchChoice>(
    context: context,
    builder: (_) => _MixMismatchDialog(analysis: analysis),
  );
  return choice ?? MismatchChoice.cancel;
}

class _MixMismatchDialog extends StatelessWidget {
  const _MixMismatchDialog({required this.analysis});

  final GasAnalysis analysis;

  /// `O2 32.1 %`, with `, He 20.0 %` when helium is part of the story: the
  /// desired mix has some, or the analysis found more than sensor offset.
  String _analysedText(DesiredMix desired) {
    final o2 = 'O2 ${analysis.o2Percent.toStringAsFixed(1)} %';
    final heliumMatters = desired.hePercent > 0 ||
        analysis.hePercent >= kHeliumNoiseFloorPercent;
    if (!heliumMatters) return o2;
    return '$o2, He ${analysis.hePercent.toStringAsFixed(1)} %';
  }

  @override
  Widget build(BuildContext context) {
    final desired = analysis.desiredMix!;
    final analysed = analysis.mixName;
    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      title: ColoredBox(
        key: const ValueKey('mix-mismatch-header'),
        color: SafetyColors.alertCriticalSurface,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: SafetyColors.onAlert,
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(
                  'Mix does not conform to analysis',
                  style: AppTypography.title.copyWith(
                    color: SafetyColors.onAlert,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      content: Text(
        'Desired ${desired.name}, analysed ${_analysedText(desired)} '
        '($analysed). The label will show $analysed.',
      ),
      actions: [
        TextButton(
          key: const ValueKey('mix-mismatch-cancel'),
          onPressed: () => Navigator.of(context).pop(MismatchChoice.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('mix-mismatch-change'),
          onPressed: () => Navigator.of(context).pop(MismatchChoice.changeMix),
          child: const Text('Change desired mix'),
        ),
        FilledButton(
          key: const ValueKey('mix-mismatch-print'),
          onPressed: () =>
              Navigator.of(context).pop(MismatchChoice.printAnalysed),
          child: Text('Print as $analysed'),
        ),
      ],
    );
  }
}
