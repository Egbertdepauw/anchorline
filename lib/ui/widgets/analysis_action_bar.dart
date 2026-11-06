/// The Analyse tab's action bar (spec §4.1 item 7): pinned at the bottom of
/// the tab, above the bottom nav; on wide, at the bottom of the save column.
///
/// With a label printer set up it holds an outlined **Save**, the filled
/// **Save & print** (the screen's one primary action) and the copies
/// stepper. Without one, a single filled **Save** across the bar; the
/// "Set up label printer" link is in the save section.
///
/// While Log on OK is running an OK press saves, so the bar is empty, except
/// for room air, which OK doesn't log.
library;

import 'package:flutter/material.dart';

import '../../analyzer/bridge/record_to_analysis.dart' show isRoomAir;
import '../theme/tokens.dart';
import 'analysis_save_controller.dart';
import 'label_print_controls.dart';

/// The height of the bar's buttons and stepper: the touch-target floor.
const double kAnalysisActionHeight = 44;

/// The bar's height: a 1 pt top border, 9 + 10 pt padding and the buttons
/// (spec §4.1 height budget).
const double kAnalysisActionBarHeight = 64;

/// The margin of a floating SnackBar about a save made from the bar: the
/// usual 10 pt above the bottom, plus the bar, so "Saved …" and a print
/// failure's Retry don't cover the buttons for the next cylinder. The app's
/// SnackBars float above the shell's bottom nav, which is where the bar is.
const EdgeInsets kSnackBarClearOfActionBar =
    EdgeInsets.fromLTRB(15, 5, 15, 10 + kAnalysisActionBarHeight);

class AnalysisActionBar extends StatelessWidget {
  const AnalysisActionBar({super.key, required this.controller});

  /// The save form whose actions the bar offers.
  final AnalysisSaveController controller;

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: controller, builder: (context, _) {
        final c = controller;
        final gas = c.usableGas;
        final roomAir = gas != null && isRoomAir(gas.o2, gas.he);
        if (c.okMode && !roomAir) return const SizedBox.shrink();
        final palette = context.palette;
        return SafeArea(
          top: false,
          child: Container(
            key: const ValueKey('analysis-action-bar'),
            decoration: BoxDecoration(
              color: palette.surfaceCard,
              border: Border(top: BorderSide(color: palette.surfaceBezel)),
            ),
            // 1 + 9 + 44 + 10 = 64 pt, the spec's height budget.
            padding: const EdgeInsets.fromLTRB(Spacing.lg, 9, Spacing.lg, 10),
            child: SizedBox(
              height: kAnalysisActionHeight,
              child: c.printReady
                  ? _withPrinter(context)
                  : _saveOnly(context),
            ),
          ),
        );
      });

  static const _shape = WidgetStatePropertyAll<OutlinedBorder>(
    RoundedRectangleBorder(borderRadius: Radii.buttonBr),
  );

  /// Shared by the buttons: 44 pt high on every platform, a little side
  /// padding so a label scaled up for large text still fits.
  static ButtonStyle _base() => ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(
            Size(kAnalysisActionHeight, kAnalysisActionHeight)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: Spacing.md)),
        shape: _shape,
        textStyle: WidgetStatePropertyAll(
            AppTypography.body.copyWith(fontWeight: FontWeight.w600)),
      );

  VoidCallback? _onSave(BuildContext context, {bool print = false}) =>
      controller.canSave
          ? () => controller.save(context, print: print)
          : null;

  /// One filled Save, full width.
  Widget _saveOnly(BuildContext context) => FilledButton(
        key: const ValueKey('analysis-save'),
        style: _base(),
        onPressed: _onSave(context),
        child: const _Label('Save'),
      );

  /// Outlined Save, filled Save & print, and the copies. On a narrow bar
  /// (a small phone, or large text) Save is narrower and the print icon
  /// goes, so "Save & print" stays readable.
  Widget _withPrinter(BuildContext context) {
    final palette = context.palette;
    return LayoutBuilder(builder: (context, constraints) {
      final roomy = constraints.maxWidth >= 340 &&
          MediaQuery.textScalerOf(context).scale(14) <= 16;
      final savePrint = roomy
          ? FilledButton.icon(
              key: const ValueKey('analysis-save-print'),
              style: _base(),
              onPressed: _onSave(context, print: true),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const _Label('Save & print'),
            )
          : FilledButton(
              key: const ValueKey('analysis-save-print'),
              style: _base(),
              onPressed: _onSave(context, print: true),
              child: const _Label('Save & print'),
            );
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: roomy ? 84 : 64,
            child: OutlinedButton(
              key: const ValueKey('analysis-save'),
              style: _base().copyWith(
                side: WidgetStateProperty.resolveWith((states) => BorderSide(
                      color: states.contains(WidgetState.disabled)
                          ? palette.surfaceRaised
                          : palette.surfaceBezel,
                    )),
              ),
              onPressed: _onSave(context),
              child: const _Label('Save'),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(child: savePrint),
          const SizedBox(width: Spacing.sm),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: palette.surfaceBezel),
              borderRadius: Radii.buttonBr,
            ),
            child: Center(
              child: CopiesStepper(
                value: controller.copies,
                onChanged: controller.setCopies,
              ),
            ),
          ),
        ],
      );
    });
  }
}

/// A button label that shrinks rather than overflows when the text is
/// large and the bar narrow.
class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text, maxLines: 1),
      );
}
