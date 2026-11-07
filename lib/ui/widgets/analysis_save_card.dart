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
/// Log on OK (issue #113, spec §4.4) starts from the outlined "Log on OK"
/// button at the right of the heading. While it runs (a [UsbOkLogger] is
/// bound) the heading says "● Logging on OK", the section is the setup for
/// the OK presses (its fields are what the next OK press saves), a "Print a
/// label on each OK" row shows with a printer set up, and the outcome of the
/// last press shows with Edit. The action bar is then the status strip with
/// Stop.
///
/// The section is a view: the form's state and its save logic live in the
/// [AnalysisSaveController] it is given.
library;

import 'package:flutter/material.dart';

import '../../analysis/mix_match.dart';
import '../../analyzer/bridge/bridge_protocol.dart';
import '../../analyzer/bridge/record_to_analysis.dart';
import '../../analyzer/stability.dart';
import '../../analyzer/usb_ok_logger.dart';
import '../../data/db/gas_analyses_dao.dart';
import '../components/section_header.dart';
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';
import 'analysis_fields.dart';
import 'analysis_save_controller.dart';
import 'desired_mix_picker.dart';
import 'label_print_controls.dart';

class AnalysisSaveCard extends StatefulWidget {
  const AnalysisSaveCard({
    super.key,
    required this.controller,
    this.onSetUpPrinter,
    this.offersLogOnOk = false,
    this.onStartLogOnOk,
  });

  /// The form's state and actions.
  final AnalysisSaveController controller;

  /// Opens the label printer settings, for the "Set up label printer" link.
  final VoidCallback? onSetUpPrinter;

  /// The heading has the "Log on OK" start button: there is a log and the
  /// source is not the demo. False hides it.
  final bool offersLogOnOk;

  /// Starts Log on OK; null disables the button (not connected).
  final VoidCallback? onStartLogOnOk;

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
    // OK doesn't log air, so the strip offers Save for it.
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
      // The heading row is a 44 pt target high (the Log on OK button) and
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
                if (okMode)
                  // Drawn like the heading, in the accent colour.
                  const SectionHeader(
                    '● Logging on OK',
                    key: ValueKey('analysis-ok-running'),
                  )
                else if (widget.offersLogOnOk)
                  _startButton(),
              ],
            ),
          ),
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
                AnalysisVerdict(
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
            // A check on a role the diver set, which stays for every OK
            // press; none on the rule's.
            showSelectedIcon: c.roleTapped,
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
            // Lets a tap on the role already shown through (as an empty
            // selection): it is the diver's choice as much as the other.
            emptySelectionAllowed: true,
            onSelectionChanged: (s) => c.tapRole(s.isEmpty ? c.role : s.first),
          ),
          const SizedBox(height: Spacing.sm),
          _pair(
            AnalysisFieldBox(
              label: 'Cylinder',
              child: _cylinderDropdown(),
            ),
            AnalysisFieldBox(
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
            AnalysisFieldBox(
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
            AnalysisFieldBox(
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
            AnalysisFieldBox(
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
          if (okMode && printReady) ...[
            const SizedBox(height: Spacing.xs),
            _printOnOkRow(),
          ],
          if (okMode && c.okResult != null) ...[
            const SizedBox(height: Spacing.sm),
            _okResultRow(c.okResult!),
          ],
          if (okMode) ...[
            const SizedBox(height: Spacing.xs),
            // Next to Stop, below: logging needs the app, not this tab.
            Text(
              'Keep Anchorline open',
              key: const ValueKey('analysis-ok-keep-open'),
              textAlign: TextAlign.end,
              style: AppTypography.caption.copyWith(color: palette.textMuted),
            ),
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

  /// An input with no decoration of its own: the [AnalysisFieldBox] draws it.
  static InputDecoration _bare(BuildContext context, {String? hint}) =>
      analysisBareDecoration(context, hint: hint);

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

  /// The outlined "Log on OK" start button with its ring icon: 44 pt high,
  /// disabled until a real analyzer is connected.
  Widget _startButton() {
    final palette = context.palette;
    return OutlinedButton.icon(
      key: const ValueKey('analyzer-log-on-ok'),
      onPressed: widget.onStartLogOnOk,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: Spacing.md)),
        shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: Radii.buttonBr)),
        textStyle: WidgetStatePropertyAll(AppTypography.body
            .copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? palette.textMuted
                : palette.textPrimary),
        iconColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? palette.textMuted
                : palette.accentPrimary),
        side: WidgetStateProperty.resolveWith((states) => BorderSide(
              color: states.contains(WidgetState.disabled)
                  ? palette.surfaceRaised
                  : palette.surfaceBezel,
            )),
      ),
      icon: const Icon(Icons.radio_button_unchecked, size: 14),
      label: const Text('Log on OK', maxLines: 1),
    );
  }

  /// "Print a label on each OK", with the copies while it is on (the strip
  /// has none), and its switch. Only while running with a printer set up.
  Widget _printOnOkRow() {
    final on = _c.printOnOk;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _c.setPrintOnOk(!on),
              child: Text(
                'Print a label on each OK',
                style: AppTypography.body
                    .copyWith(color: context.palette.textPrimary),
              ),
            ),
          ),
          if (on)
            CopiesStepper(
              value: _c.copies,
              onChanged: _c.setCopies,
            ),
          const SizedBox(width: Spacing.xs),
          Switch(
            key: const ValueKey('analysis-print-on-ok'),
            value: on,
            onChanged: _c.setPrintOnOk,
          ),
        ],
      ),
    );
  }

  /// How the latest OK press went: an icon, the message and Edit for the
  /// entry it saved, with a 3 pt edge on the left in the result's colour.
  /// Delete is in the edit sheet.
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
    final side = BorderSide(color: palette.surfaceRaised);
    return Container(
      key: const ValueKey('analysis-ok-result-row'),
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        color: palette.surfaceCard,
        border: Border(
          left: BorderSide(color: color, width: 3),
          top: side,
          right: side,
          bottom: side,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
              child: Text(
                message,
                key: const ValueKey('analysis-ok-result'),
                style: AppTypography.body
                    .copyWith(fontSize: 13, color: palette.textPrimary),
              ),
            ),
          ),
          if (r.analysisId != null)
            TextButton(
              key: const ValueKey('analysis-ok-edit'),
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.standard,
                textStyle: AppTypography.body
                    .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              onPressed: _c.okBusy ? null : () => _c.editResult(context),
              child: const Text('Edit'),
            )
          else
            const SizedBox(width: 10),
        ],
      ),
    );
  }
}
