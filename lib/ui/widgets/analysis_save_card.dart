/// "Save analysis" card on the gas-analyzer screen (issue #111).
///
/// Captures the current reading plus the diver's context (cylinder from
/// Equipment, who analysed, fill pressure, notes) into the synced
/// cylinder analysis log. A reading that isn't STABLE asks for
/// confirmation first; it's never blocked, because a diver at the fill
/// station sometimes has to log what they've got.
///
/// For cylinder labels (issue #114) the diver can also state the desired
/// mix, graded live against the reading, and the gas role. With a label
/// printer set up, "Save & print" saves the analysis and then prints its
/// label. A hard mismatch with the desired mix is confirmed before
/// anything is saved; a print that fails leaves the analysis saved.
///
/// With a [UsbOkLogger] (issue #113, Log on OK over USB) the card becomes the
/// setup for the OK presses: its fields are what the next OK press saves, the
/// Save buttons give way to a hint, and the outcome of each press shows on
/// the card with Edit and Delete. Room air is the exception, because OK does
/// not log it: the Save buttons stay.
///
/// The card is a view: the form's state and its save logic live in the
/// [AnalysisSaveController] it is given.
library;

import 'package:flutter/material.dart';

import '../../analyzer/bridge/bridge_protocol.dart';
import '../../analyzer/bridge/record_to_analysis.dart';
import '../../analyzer/stability.dart';
import '../../analyzer/usb_ok_logger.dart';
import '../../data/db/gas_analyses_dao.dart';
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';
import 'analysis_save_controller.dart';
import 'desired_mix_picker.dart';
import 'label_print_controls.dart';
import 'mix_match_indicator.dart';

class AnalysisSaveCard extends StatefulWidget {
  const AnalysisSaveCard({
    super.key,
    required this.controller,
    this.onSetUpPrinter,
  });

  /// The form's state and actions.
  final AnalysisSaveController controller;

  /// Opens the label printer settings, for the "Set up label printer" link.
  final VoidCallback? onSetUpPrinter;

  @override
  State<AnalysisSaveCard> createState() => _AnalysisSaveCardState();
}

class _AnalysisSaveCardState extends State<AnalysisSaveCard> {
  /// Leaving the "Analysed by" field ends its edit, which writes the name.
  final _diverFocus = FocusNode();

  AnalysisSaveController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _diverFocus.addListener(_onDiverFocus);
  }

  @override
  void dispose() {
    _diverFocus.removeListener(_onDiverFocus);
    _diverFocus.dispose();
    super.dispose();
  }

  void _onDiverFocus() {
    if (!_diverFocus.hasFocus) _c.rememberAnalysedBy();
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: _c, builder: (_, _) => _card());

  Widget _card() {
    final palette = context.palette;
    final c = _c;
    final gas = c.usableGas;
    final usable = gas != null;
    final stable = c.stability == ReadingStability.stable;
    final desired = c.desiredMix;
    final printing = c.labelPrinting;
    final printReady = c.printReady;
    final okMode = c.okMode;
    final roomAir = gas != null && isRoomAir(gas.o2, gas.he);
    // OK doesn't log air, so the Save buttons stay for it.
    final showSave = !okMode || roomAir;
    // A cylinder deleted elsewhere (sync) drops out of the list; don't
    // leave the dropdown pointing at a value it no longer has.
    final selected = c.cylinderId;
    final canSave = c.canSave;
    final onSave = canSave ? () => c.save(context) : null;
    const saveIcon = Icon(Icons.save_alt);
    const saveLabel = Text('Save analysis');
    return Container(
      key: const ValueKey('analysis-save-card'),
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: palette.surfaceCard,
        border: Border.all(color: palette.surfaceRaised),
        borderRadius: Radii.cardBr,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'SAVE ANALYSIS',
            style: AppTypography.label.copyWith(
              color: palette.textMuted,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Column(
            key: c.mixRowKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mix (optional)',
                style:
                    AppTypography.caption.copyWith(color: palette.textMuted),
              ),
              const SizedBox(height: Spacing.xs),
              DesiredMixPicker(
                options: c.mixOptions,
                selected: desired,
                onChanged: c.pickMix,
              ),
              // Only for a usable reading: grading NaN throws.
              if (desired != null && gas != null) ...[
                const SizedBox(height: Spacing.sm),
                MixMatchIndicator(
                  o2Percent: gas.o2,
                  hePercent: gas.he,
                  desired: desired,
                ),
              ],
            ],
          ),
          const SizedBox(height: Spacing.sm),
          SegmentedButton<GasRole>(
            key: const ValueKey('analysis-gas-role'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: GasRole.diluent, label: Text('Diluent')),
              ButtonSegment(
                  value: GasRole.bailout, label: Text('Bailout/deco')),
            ],
            selected: {c.role},
            onSelectionChanged: (s) => c.tapRole(s.first),
          ),
          const SizedBox(height: Spacing.sm),
          DropdownButtonFormField<String?>(
            key: const ValueKey('analysis-cylinder'),
            initialValue: selected,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Cylinder (optional)',
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('No cylinder')),
              for (final cyl in c.cylinders)
                DropdownMenuItem<String?>(
                  value: cyl.id,
                  child: Text(cyl.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: c.selectCylinder,
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('analysis-diver'),
                  controller: c.analysedBy,
                  focusNode: _diverFocus,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Analysed by',
                    isDense: true,
                  ),
                  onSubmitted: (_) => c.rememberAnalysedBy(),
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: TextField(
                  key: const ValueKey('analysis-pressure'),
                  controller: c.fillPressure,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Fill pressure (bar)',
                    isDense: true,
                    errorText: c.fillPressureValid
                        ? null
                        : 'Enter a pressure in bar',
                    errorMaxLines: 2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            key: const ValueKey('analysis-for'),
            controller: c.analysedFor,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'For (optional)',
              isDense: true,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            key: const ValueKey('analysis-notes'),
            controller: c.notes,
            decoration: const InputDecoration(
              labelText: 'Notes',
              isDense: true,
            ),
          ),
          const SizedBox(height: Spacing.md),
          if (usable && !stable) ...[
            Row(
              key: const ValueKey('analysis-unstable-hint'),
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 16, color: SafetyColors.warning),
                const SizedBox(width: Spacing.xs),
                Expanded(
                  child: Text(
                    // An OK press is the confirmation; it saves the reading
                    // marked not stable (decision 18). The manual Save still
                    // asks to wait.
                    !showSave
                        ? 'Not stable yet. An OK press now saves it marked '
                            'not stable.'
                        : 'Reading not stable yet. Wait for STABLE before '
                            'saving.',
                    style: AppTypography.caption
                        .copyWith(color: SafetyColors.warning),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
          ],
          if (okMode) ...[
            _printOnOkRow(printReady: printReady, showCopies: !showSave),
            _okHint(roomAir),
            if (showSave) const SizedBox(height: Spacing.sm),
          ],
          if (showSave && !printReady)
            FilledButton.icon(
              key: const ValueKey('analysis-save'),
              onPressed: onSave,
              icon: saveIcon,
              label: saveLabel,
            )
          else if (showSave)
            // Wraps on a phone: "Save & print" and its copies stay
            // together on the second line.
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('analysis-save'),
                  onPressed: onSave,
                  icon: saveIcon,
                  label: saveLabel,
                ),
                Wrap(
                  spacing: Spacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('analysis-save-print'),
                      onPressed: canSave
                          ? () => c.save(context, print: true)
                          : null,
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Save & print'),
                    ),
                    CopiesStepper(
                      value: c.copies,
                      onChanged: c.setCopies,
                    ),
                  ],
                ),
              ],
            ),
          if (printing != null &&
              !printReady &&
              widget.onSetUpPrinter != null) ...[
            const SizedBox(height: Spacing.xs),
            TextButton.icon(
              key: const ValueKey('analysis-setup-printer'),
              onPressed: widget.onSetUpPrinter,
              icon: const Icon(Icons.print_outlined),
              label: const Text('Set up label printer'),
            ),
          ],
          if (okMode && c.okResult != null) ...[
            const SizedBox(height: Spacing.sm),
            _okResultRow(c.okResult!),
          ],
        ],
      ),
    );
  }

  /// "Print label on OK", with the copies while the Save buttons (which
  /// carry their own) are away. Off and disabled without a printer.
  Widget _printOnOkRow({required bool printReady, required bool showCopies}) {
    final on = printReady && _c.printOnOk;
    return Row(
      children: [
        Expanded(
          // A ListTile paints on the nearest Material, and the card's own
          // background would hide its ink.
          child: Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: const ValueKey('analysis-print-on-ok'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Print label on OK'),
              value: on,
              onChanged: printReady ? _c.setPrintOnOk : null,
            ),
          ),
        ),
        if (on && showCopies)
          CopiesStepper(
            value: _c.copies,
            onChanged: _c.setCopies,
          ),
      ],
    );
  }

  /// What to do in Log on OK mode: press OK, or, for room air, tap Save.
  Widget _okHint(bool roomAir) {
    final palette = context.palette;
    return Row(
      key: const ValueKey('analysis-ok-hint'),
      children: [
        Icon(Icons.touch_app_outlined, size: 18, color: palette.textSecondary),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: Text(
            roomAir
                ? "Air isn't logged on OK. Tap Save."
                : 'Press OK on the SOLO to save',
            style: AppTypography.body.copyWith(color: palette.textSecondary),
          ),
        ),
      ],
    );
  }

  /// How the latest OK press went, with Edit and Delete for the entry it
  /// saved.
  Widget _okResultRow(OkLogResult r) {
    final palette = context.palette;
    final (message, icon, color) = switch (r.code) {
      // The label is out but the entry could not be signed off in the log.
      FeedbackCode.printed when !r.complete => (
          'Printed ${r.text} — sign off in the log',
          Icons.print_outlined,
          SafetyColors.warning,
        ),
      FeedbackCode.printed => (
          'Printed ${r.text}',
          Icons.print_outlined,
          SafetyColors.success,
        ),
      FeedbackCode.saved when r.complete => (
          'Saved ${r.text}',
          Icons.check_circle_outline,
          SafetyColors.success,
        ),
      FeedbackCode.saved => (
          'Saved, needs sign-off: ${r.text}',
          Icons.warning_amber_rounded,
          SafetyColors.warning,
        ),
      FeedbackCode.check => (
          'Needs sign-off: ${r.text}',
          Icons.warning_amber_rounded,
          SafetyColors.warning,
        ),
      FeedbackCode.skipped => (
          'Room air: not logged',
          Icons.info_outline,
          palette.textMuted,
        ),
      FeedbackCode.error => (
          'Not saved: ${r.text}',
          Icons.error_outline,
          SafetyColors.danger,
        ),
    };
    final hasEntry = r.analysisId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                message,
                key: const ValueKey('analysis-ok-result'),
                style: AppTypography.body.copyWith(color: palette.textPrimary),
              ),
            ),
          ],
        ),
        if (hasEntry)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                key: const ValueKey('analysis-ok-edit'),
                onPressed: _c.okBusy ? null : () => _c.editResult(context),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
              TextButton.icon(
                key: const ValueKey('analysis-ok-delete'),
                onPressed:
                    _c.okBusy ? null : () => _c.deleteResult(context),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
            ],
          ),
      ],
    );
  }
}
