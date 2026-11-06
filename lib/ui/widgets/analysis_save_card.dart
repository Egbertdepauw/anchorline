/// The "Save analysis" section of the Analyse tab (issues #111, #113, #114;
/// spec §4.1 item 6).
///
/// Captures the current reading plus the diver's context (cylinder from
/// Equipment, who analysed, fill pressure, notes) into the synced cylinder
/// analysis log. The section holds the form: the desired mix chips with
/// their verdict line, the gas role, two rows of dense fields, "+ Add a
/// note", and the hints. Its buttons are in the `AnalysisActionBar` pinned
/// under the tab.
///
/// The desired mix is picked automatically (the nearest standard mix or the
/// Blend target, spec §4.3) and the verdict line says where it came from. A
/// chip the diver taps is their pick until the next manual save.
///
/// With a [UsbOkLogger] (issue #113, Log on OK over USB) the section becomes
/// the setup for the OK presses: its fields are what the next OK press saves,
/// a hint says to press OK, and the outcome of each press shows with Edit and
/// Delete.
///
/// The section is a view: the form's state and its save logic live in the
/// [AnalysisSaveController] it is given.
library;

import 'package:flutter/material.dart';

import '../../analysis/mix_match.dart';
import '../../analysis/standard_mix_pick.dart';
import '../../analyzer/bridge/bridge_protocol.dart';
import '../../analyzer/bridge/record_to_analysis.dart';
import '../../analyzer/stability.dart';
import '../../analyzer/usb_ok_logger.dart';
import '../../data/db/gas_analyses_dao.dart';
import '../components/section_header.dart';
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';
import 'analysis_save_controller.dart';
import 'desired_mix_picker.dart';
import 'label_print_controls.dart';
import 'mix_match_indicator.dart' show mixMatchColor;

/// The height of the section's fields on the Analyse tab (spec §4.1 height
/// budget). They grow with large text.
const double kAnalysisFieldHeight = 40;

class AnalysisSaveCard extends StatefulWidget {
  const AnalysisSaveCard({
    super.key,
    required this.controller,
    this.onSetUpPrinter,
    this.headingTrailing,
    this.headingNote,
  });

  /// The form's state and actions.
  final AnalysisSaveController controller;

  /// Opens the label printer settings, for the "Set up label printer" link.
  final VoidCallback? onSetUpPrinter;

  /// At the right of the "Save analysis" heading: the Log on OK control.
  final Widget? headingTrailing;

  /// A line under the heading, about Log on OK.
  final Widget? headingNote;

  @override
  State<AnalysisSaveCard> createState() => _AnalysisSaveCardState();
}

class _AnalysisSaveCardState extends State<AnalysisSaveCard> {
  // A tap anywhere on a field's box, its label included, focuses its input.
  final _pressureFocus = FocusNode();
  final _diverFocus = FocusNode();
  final _forFocus = FocusNode();
  final _notesFocus = FocusNode();

  AnalysisSaveController get _c => widget.controller;

  @override
  void dispose() {
    _pressureFocus.dispose();
    _diverFocus.dispose();
    _forFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: _c, builder: (_, _) => _section());

  Widget _section() {
    final palette = context.palette;
    final c = _c;
    final gas = c.usableGas;
    final usable = gas != null;
    final stable = c.stability == ReadingStability.stable;
    final desired = c.desiredMix;
    final printReady = c.printReady;
    final okMode = c.okMode;
    final roomAir = gas != null && isRoomAir(gas.o2, gas.he);
    // OK doesn't log air, so the Save buttons stay for it.
    final showSave = !okMode || roomAir;
    // Without a printer the bar has Save only, and this sets one up.
    final setUpPrinter = c.labelPrinting != null &&
            !printReady &&
            widget.onSetUpPrinter != null
        ? Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: _link(
              key: const ValueKey('analysis-setup-printer'),
              icon: Icons.print_outlined,
              label: 'Set up label printer',
              onPressed: widget.onSetUpPrinter,
            ),
          )
        : null;
    return Container(
      key: const ValueKey('analysis-save-card'),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.surfaceRaised)),
      ),
      // The heading row is a 44 pt target high (the Log on OK control) and
      // takes the place of the section's 10 pt top padding (spec §4.1
      // height budget).
      padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(
              children: [
                const Expanded(child: SectionHeader('Save analysis')),
                ?widget.headingTrailing,
              ],
            ),
          ),
          if (widget.headingNote != null) ...[
            widget.headingNote!,
            const SizedBox(height: Spacing.xs),
          ],
          const SizedBox(height: 2),
          Column(
            key: c.mixRowKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DesiredMixPicker(
                options: c.mixOptions,
                selected: desired,
                onChanged: c.pickMix,
                dense: true,
              ),
              // Only for a usable reading: grading NaN throws.
              if (desired != null && gas != null) ...[
                const SizedBox(height: 6),
                _Verdict(
                  match: gradeMix(
                    o2Percent: gas.o2,
                    hePercent: gas.he,
                    targetO2Percent: desired.o2Percent,
                    targetHePercent: desired.hePercent,
                  ),
                  mix: desired,
                  source: c.mixSource,
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<GasRole>(
            key: const ValueKey('analysis-gas-role'),
            showSelectedIcon: false,
            expandedInsets: EdgeInsets.zero,
            // 36 pt high on every platform: the segments are text buttons
            // (40 pt) one density step down (spec §4.1 height budget).
            style: const ButtonStyle(
              padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: Spacing.md)),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity(vertical: -1),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: Radii.buttonBr),
              ),
            ),
            segments: const [
              ButtonSegment(
                value: GasRole.diluent,
                label: Text('Diluent',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              ButtonSegment(
                value: GasRole.bailout,
                label: Text('Bailout / deco',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
            selected: {c.role},
            onSelectionChanged: (s) => c.tapRole(s.first),
          ),
          const SizedBox(height: Spacing.sm),
          _pair(
            _FieldBox(
              label: 'Cylinder',
              child: _cylinderDropdown(),
            ),
            _FieldBox(
              label: 'Fill pressure',
              focusNode: _pressureFocus,
              error: !c.fillPressureValid,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('analysis-pressure'),
                      controller: c.fillPressure,
                      focusNode: _pressureFocus,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      style: _inputStyle(context),
                      decoration: _bare(context),
                    ),
                  ),
                  const SizedBox(width: Spacing.xs),
                  Text('bar', style: _unitStyle(context)),
                ],
              ),
            ),
          ),
          if (!c.fillPressureValid)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.xs),
              child: Text(
                'Enter a pressure in bar',
                textAlign: TextAlign.end,
                style:
                    AppTypography.caption.copyWith(color: SafetyColors.danger),
              ),
            ),
          const SizedBox(height: Spacing.sm),
          _pair(
            _FieldBox(
              label: 'Analysed by',
              focusNode: _diverFocus,
              child: TextField(
                key: const ValueKey('analysis-diver'),
                controller: c.analysedBy,
                focusNode: _diverFocus,
                textCapitalization: TextCapitalization.words,
                style: _inputStyle(context),
                decoration: _bare(context, hint: 'Initials'),
              ),
            ),
            _FieldBox(
              label: 'For',
              focusNode: _forFocus,
              child: TextField(
                key: const ValueKey('analysis-for'),
                controller: c.analysedFor,
                focusNode: _forFocus,
                textCapitalization: TextCapitalization.words,
                style: _inputStyle(context),
                decoration: _bare(context, hint: 'Optional'),
              ),
            ),
          ),
          const SizedBox(height: Spacing.xs),
          if (c.notesShown) ...[
            _FieldBox(
              label: 'Notes',
              focusNode: _notesFocus,
              child: TextField(
                key: const ValueKey('analysis-notes'),
                controller: c.notes,
                focusNode: _notesFocus,
                autofocus: !okMode,
                minLines: 1,
                maxLines: 3,
                style: _inputStyle(context),
                decoration: _bare(context),
              ),
            ),
            ?setUpPrinter,
          ] else
            // On one line when they fit, so a phone without a printer still
            // has the tab on one screen.
            Wrap(
              spacing: Spacing.lg,
              children: [
                _link(
                  key: const ValueKey('analysis-add-note'),
                  label: '+ Add a note',
                  onPressed: c.openNotes,
                ),
                ?setUpPrinter,
              ],
            ),
          if (usable && !stable) ...[
            const SizedBox(height: Spacing.xs),
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
          ],
          if (okMode) ...[
            const SizedBox(height: Spacing.xs),
            _printOnOkRow(printReady: printReady, showCopies: !showSave),
            _okHint(roomAir),
          ],
          if (okMode && c.okResult != null) ...[
            const SizedBox(height: Spacing.sm),
            _okResultRow(c.okResult!),
          ],
        ],
      ),
    );
  }

  /// Two fields side by side, the same height.
  Widget _pair(Widget left, Widget right) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: left),
            const SizedBox(width: Spacing.sm),
            Expanded(child: right),
          ],
        ),
      );

  Widget _cylinderDropdown() {
    final palette = context.palette;
    final c = _c;
    final style = _inputStyle(context);
    return DropdownButtonHideUnderline(
      child: DropdownButton<String?>(
        key: const ValueKey('analysis-cylinder'),
        // A cylinder deleted elsewhere (sync) drops out of the list; the
        // controller doesn't leave the dropdown pointing at it.
        value: c.cylinderId,
        isExpanded: true,
        isDense: true,
        iconSize: 18,
        iconEnabledColor: palette.textMuted,
        style: style,
        dropdownColor: palette.surfaceRaised,
        items: [
          DropdownMenuItem<String?>(
            value: null,
            child: Text('No cylinder',
                overflow: TextOverflow.ellipsis,
                style: style.copyWith(color: palette.textMuted)),
          ),
          for (final cyl in c.cylinders)
            DropdownMenuItem<String?>(
              value: cyl.id,
              child: Text(cyl.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: c.selectCylinder,
      ),
    );
  }

  static TextStyle _inputStyle(BuildContext context) =>
      AppTypography.body.copyWith(color: context.palette.textPrimary);

  static TextStyle _unitStyle(BuildContext context) =>
      AppTypography.body.copyWith(color: context.palette.textMuted);

  /// An input with no decoration of its own: the [_FieldBox] draws it.
  static InputDecoration _bare(BuildContext context, {String? hint}) =>
      InputDecoration(
        isDense: true,
        filled: false,
        contentPadding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        hintText: hint,
        hintStyle: _unitStyle(context),
      );

  /// A text link in the accent colour ("+ Add a note", "Set up label
  /// printer"), drawn as a line of text. Its target is 32 pt high, the
  /// chips' floor, as the tab's height budget leaves no room for 44.
  Widget _link({
    required Key key,
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
  }) {
    final style = TextButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      alignment: Alignment.centerLeft,
      textStyle: AppTypography.body
          .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
    );
    return icon == null
        ? TextButton(
            key: key, style: style, onPressed: onPressed, child: Text(label))
        : TextButton.icon(
            key: key,
            style: style,
            onPressed: onPressed,
            icon: Icon(icon, size: 16),
            label: Text(label),
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
          Wrap(
            alignment: WrapAlignment.end,
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

/// The verdict on the desired mix, in the match colour with a dot, e.g.
/// "Matches Tx21/35, the nearest standard mix". The suffix says where an
/// automatic pick came from; a diver's pick has none.
class _Verdict extends StatelessWidget {
  const _Verdict({required this.match, required this.mix, this.source});

  final MixMatch match;
  final DesiredMix mix;
  final MixPickSource? source;

  @override
  Widget build(BuildContext context) {
    final color = mixMatchColor(match.level);
    final suffix = switch (source) {
      MixPickSource.standard => ', the nearest standard mix',
      MixPickSource.blendTarget => ', the Blend target',
      null => '',
    };
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${mixMatchText(match, mix.name)}$suffix',
            key: const ValueKey('analysis-verdict'),
            style: AppTypography.label.copyWith(
              color: color,
              height: 1.25,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

/// A dense field (spec §2): filled `surfaceCard`, a 1 px `surfaceBezel`
/// border (accent while focused, red on an error), a 2 px radius, and a
/// small label inside at the top. At least [kAnalysisFieldHeight] high. A
/// tap anywhere on it focuses [focusNode].
class _FieldBox extends StatefulWidget {
  const _FieldBox({
    required this.label,
    required this.child,
    this.focusNode,
    this.error = false,
  });

  final String label;
  final Widget child;
  final FocusNode? focusNode;
  final bool error;

  @override
  State<_FieldBox> createState() => _FieldBoxState();
}

class _FieldBoxState extends State<_FieldBox> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final borderColor = widget.error
        ? SafetyColors.danger
        : _focused
            ? palette.accentPrimary
            : palette.surfaceBezel;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => setState(() => _focused = f),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.focusNode?.requestFocus,
        child: Container(
          constraints: const BoxConstraints(minHeight: kAnalysisFieldHeight),
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 1),
          decoration: BoxDecoration(
            color: palette.surfaceCard,
            border: Border.all(color: borderColor),
            borderRadius: Radii.cardBr,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                    fontSize: 10.5, height: 1.0, color: palette.textMuted),
              ),
              widget.child,
            ],
          ),
        ),
      ),
    );
  }
}
