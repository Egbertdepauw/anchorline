/// The Analyse tab's action bar (spec §4.1 item 7): pinned at the bottom of
/// the tab, above the bottom nav; on wide, at the bottom of the save column.
///
/// With a label printer set up it holds an outlined **Save**, the filled
/// **Save & print** (the screen's one primary action) and the copies
/// stepper. Without one, a single filled **Save** across the bar; the
/// "Set up label printer" link is in the save section.
///
/// While Log on OK is running (spec §4.4) the bar becomes a status strip:
/// accent-tinted, with a dot that pulses with each line from the SOLO, two
/// lines of text, and **Stop**. Held on the SOLO, the dot is grey and still.
/// For room air, which OK doesn't log, the strip has a filled **Save** before
/// Stop.
library;

import 'dart:math' as math;

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
  const AnalysisActionBar({
    super.key,
    required this.controller,
    this.okHeld = false,
    this.onStopLogOnOk,
  });

  /// The save form whose actions the bar offers.
  final AnalysisSaveController controller;

  /// Log on OK runs and the SOLO holds its reading after an OK press
  /// (`AnalyzerSession.held`).
  final bool okHeld;

  /// Stop, in the Log on OK strip; null disables it.
  final VoidCallback? onStopLogOnOk;

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: controller, builder: (context, _) {
        final c = controller;
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
              child: c.okMode
                  ? _okStrip(context)
                  : c.printReady
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

  /// The Log on OK status strip. Room air (OK doesn't log it) comes first,
  /// as only it offers Save; then held on the SOLO; else it waits for OK.
  Widget _okStrip(BuildContext context) {
    final palette = context.palette;
    final c = controller;
    final gas = c.usableGas;
    final roomAir = gas != null && isRoomAir(gas.o2, gas.he);
    final held = okHeld && !roomAir;
    final (title, subtitle) = roomAir
        ? ("Air isn't logged on OK", 'Tap Save to log it')
        : held
            ? ('Held on the SOLO', 'Press OK there to measure again')
            : ('Logging on OK', 'Press OK on the SOLO to save');
    final accent = palette.accentPrimary;
    final dot = held ? palette.textSecondary : accent;
    return DecoratedBox(
      key: const ValueKey('analyzer-ok-strip'),
      decoration: BoxDecoration(
        color: held
            ? palette.textSecondary.withValues(alpha: 0.10)
            : accent.withValues(alpha: 0.12),
        border: Border.all(
          color: held ? palette.surfaceBezel : accent.withValues(alpha: 0.55),
        ),
        borderRadius: Radii.buttonBr,
      ),
      child: Row(
        children: [
          const SizedBox(width: Spacing.md),
          _PulseDot(color: dot, pulsing: !held, beat: c.reading),
          const SizedBox(width: 10),
          Expanded(
            // Large text on a small phone shrinks the two lines rather
            // than overflow the strip.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    style: AppTypography.body.copyWith(
                      fontSize: 13.5,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    style: AppTypography.caption.copyWith(
                      fontSize: 11.5,
                      height: 1.2,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (roomAir) ...[
            const SizedBox(width: Spacing.xs),
            _StripButton(
              key: const ValueKey('analysis-ok-strip-save'),
              label: 'Save',
              filled: true,
              onPressed: _onSave(context),
            ),
          ],
          const SizedBox(width: Spacing.xs),
          _StripButton(
            key: const ValueKey('analyzer-ok-stop'),
            label: 'Stop',
            onPressed: onStopLogOnOk,
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

/// A button in the Log on OK strip: a 44 pt target, drawn as the smaller box
/// of the mockup inside it, so the strip keeps its look.
class _StripButton extends StatelessWidget {
  const _StripButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// The accent fill (room air's Save); else raised with a bezel line.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Color foreground(Set<WidgetState> states) =>
        states.contains(WidgetState.disabled)
            ? palette.textMuted
            : filled
                ? palette.textInverse
                : palette.textPrimary;
    return TextButton(
      onPressed: onPressed,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(
            Size(kAnalysisActionHeight, kAnalysisActionHeight)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: Spacing.md)),
        shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: Radii.buttonBr)),
        textStyle: WidgetStatePropertyAll(AppTypography.body
            .copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
        foregroundColor: WidgetStateProperty.resolveWith(foreground),
        // The box below shows the press; the target around it stays clear.
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
        backgroundBuilder: (context, states, child) {
          final disabled = states.contains(WidgetState.disabled);
          var fill = filled && !disabled
              ? palette.accentPrimary
              : palette.surfaceRaised;
          if (!disabled &&
              (states.contains(WidgetState.pressed) ||
                  states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused))) {
            fill = Color.alphaBlend(
                foreground(states).withValues(alpha: 0.12), fill);
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                border: filled && !disabled
                    ? null
                    : Border.all(color: palette.surfaceBezel),
                borderRadius: Radii.buttonBr,
              ),
              child: child,
            ),
          );
        },
      ),
      child: Text(label, maxLines: 1),
    );
  }
}

/// The strip's dot. While logging it pulses once with each new line from
/// the SOLO ([beat] changes), so it shows the lines are coming in; held, it
/// is still. Each pulse ends, so a test's pumpAndSettle still settles, and
/// with reduced motion there is none.
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.pulsing, this.beat});

  final Color color;
  final bool pulsing;

  /// Changes with each line: the live reading.
  final Object? beat;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
    value: 1,
  );
  bool _reduceMotion = false;

  @override
  void didUpdateWidget(_PulseDot old) {
    super.didUpdateWidget(old);
    if (!widget.pulsing) {
      _pulse.value = 1;
    } else if (!identical(old.beat, widget.beat) && !_reduceMotion) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        // At rest a 4 pt ring; a pulse swells it and brings it back.
        final swell = math.sin(math.pi * _pulse.value);
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              if (widget.pulsing)
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.25 + 0.2 * swell),
                  spreadRadius: 4 + 3 * swell,
                ),
            ],
          ),
        );
      },
    );
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
