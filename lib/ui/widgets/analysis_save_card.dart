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
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../analysis/gas_naming.dart';
import '../../analysis/mix_match.dart';
import '../../analyzer/bridge/bridge_protocol.dart';
import '../../analyzer/bridge/record_to_analysis.dart';
import '../../analyzer/protocol/analyzer_reading.dart';
import '../../analyzer/stability.dart';
import '../../analyzer/usb_ok_logger.dart';
import '../../data/db/gas_analyses_dao.dart';
import '../../labels/label_print_service.dart';
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';
import 'analysis_edit_sheet.dart';
import 'desired_mix_picker.dart';
import 'label_print_controls.dart';
import 'mix_match_indicator.dart';
import 'mix_mismatch_dialog.dart';

class AnalysisSaveCard extends StatefulWidget {
  const AnalysisSaveCard({
    super.key,
    required this.dao,
    required this.reading,
    required this.stability,
    required this.modPpo2s,
    this.blendTarget,
    this.labelPrinting,
    this.onSetUpPrinter,
    this.okLogger,
    this.initialAnalysedBy,
    this.onAnalysedByChanged,
    this.now = DateTime.now,
  });

  final GasAnalysesDaoLike dao;

  /// The live reading to save; null before the first one.
  final AnalyzerReading? reading;
  final ReadingStability stability;

  /// The ppO2 set the screen shows MODs for; stored with the analysis.
  final List<double> modPpo2s;

  /// The Blend tab's target, when the diver used it recently; offered
  /// first among the desired mixes.
  final DesiredMix? blendTarget;

  /// Prints the label of a saved analysis. With a printer set up the card
  /// offers "Save & print"; without one, the "Set up label printer" link.
  /// Null offers neither.
  final LabelPrintService? labelPrinting;

  /// Opens the label printer settings, for the "Set up label printer" link.
  final VoidCallback? onSetUpPrinter;

  /// Non-null puts the card in Log on OK mode: it is the setup of this
  /// logger and shows what its OK presses did. The card follows the logger
  /// it is given: a new one starts a new run, and a null one ends it.
  final UsbOkLogger? okLogger;

  /// The name the "Analysed by" field starts with (the one remembered from
  /// the last session). Read once, when the card is created.
  final String? initialAnalysedBy;

  /// Told the "Analysed by" text on every edit, null when it is blank, so
  /// the screen can remember it.
  final ValueChanged<String?>? onAnalysedByChanged;

  /// Clock, injectable for tests.
  final DateTime Function() now;

  @override
  State<AnalysisSaveCard> createState() => _AnalysisSaveCardState();
}

class _AnalysisSaveCardState extends State<AnalysisSaveCard> {
  final _diver = TextEditingController();
  final _for = TextEditingController();
  final _pressure = TextEditingController();
  final _notes = TextEditingController();

  /// The desired-mix row, scrolled into view on "Change desired mix".
  final _mixKey = GlobalKey();
  List<CylinderChoice> _cylinders = const [];
  String? _cylinderId;
  List<DesiredMix> _mixOptions = const [];
  DesiredMix? _desired;
  GasRole _role = GasRole.bailout;
  int _copies = 1;

  /// A save, with its confirm dialogs, is under way.
  bool _saving = false;

  /// The saved analysis is printing.
  bool _printing = false;

  bool get _busy => _saving || _printing;

  // ── Log on OK ───────────────────────────────────────────────────
  StreamSubscription<OkLogResult>? _okSub;

  /// The latest OK press of this logger, shown with Edit and Delete.
  OkLogResult? _okResult;

  /// Edit or Delete of the result is under way.
  bool _okBusy = false;

  /// "Print label on OK", once the diver has chosen; until then it is on
  /// when a printer is set up.
  bool? _printOnOk;

  /// The per-cylinder fields as the logger last took them. A press that saves
  /// complete uses them up, but only the ones still as they were: the diver
  /// may already be typing for the next cylinder while the label prints.
  ({String? cylinderId, String pressure, String notes})? _takenByOk;

  @override
  void initState() {
    super.initState();
    _diver.text = widget.initialAnalysedBy ?? '';
    _loadCylinders();
    _loadMixOptions();
    _bindLogger();
  }

  @override
  void didUpdateWidget(AnalysisSaveCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.okLogger != widget.okLogger) {
      _unbindLogger(oldWidget.okLogger);
      _okResult = null;
      _takenByOk = null;
      _bindLogger();
    }
  }

  Future<void> _loadCylinders() async {
    final list = await widget.dao.listCylinderChoices();
    if (!mounted) return;
    setState(() => _cylinders = list);
  }

  /// The desired mixes to offer: the Blend target, then the log's recent
  /// ones. Reloaded after each save, so the mix just used (perhaps typed in
  /// through "Other…") is one tap away for the next cylinder. A failed read
  /// keeps the options there are.
  Future<void> _loadMixOptions() async {
    final List<GasAnalysis> log;
    try {
      log = await widget.dao.list();
    } catch (e) {
      debugPrint('Analysis save card: loading the recent mixes failed: $e');
      return;
    }
    if (!mounted) return;
    setState(() => _mixOptions =
        recentDesiredMixes(log, blendTarget: widget.blendTarget));
  }

  @override
  void dispose() {
    _unbindLogger(widget.okLogger);
    _diver.dispose();
    _for.dispose();
    _pressure.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Becomes the setup of the logger and listens to what its presses did.
  /// The results are not replayed, so the card listens for as long as it has
  /// the logger.
  void _bindLogger() {
    final logger = widget.okLogger;
    if (logger == null) return;
    logger.setupProvider = _okSetup;
    _okSub = logger.results.listen(_onOkResult);
  }

  void _unbindLogger(UsbOkLogger? logger) {
    // Not awaited: cancelling a broadcast subscription returns a root-zone
    // future, which never completes under the fake clock of widget tests.
    unawaited(_okSub?.cancel());
    _okSub = null;
    logger?.setupProvider = null;
  }

  bool get _printReady => widget.labelPrinting?.isConfigured == true;

  /// The fields as they are now, for the OK press the logger is handling.
  OkSetup _okSetup() {
    final cylinderId =
        _cylinders.any((c) => c.id == _cylinderId) ? _cylinderId : null;
    _takenByOk =
        (cylinderId: cylinderId, pressure: _pressure.text, notes: _notes.text);
    final printReady = _printReady;
    return (
      setup: LogOnOkSetup(
        analysedBy: _diver.text,
        desiredMix: _desired,
        gasRole: _role,
        analysedFor: _blankToNull(_for.text),
        printOnOk: printReady && (_printOnOk ?? true),
        printerConfigured: printReady,
        cylinderId: cylinderId,
        fillPressureBar: _parseDecimal(_pressure.text),
        notes: _notes.text,
        modPpo2s: widget.modPpo2s,
      ),
      copies: _copies,
    );
  }

  /// Shows the outcome of an OK press. One that saved complete uses up the
  /// per-cylinder fields; a press that needs sign-off leaves them, so OK on
  /// the same cylinder again still has them. The name, desired mix, role,
  /// "for", copies and print switch stay for the next cylinder.
  void _onOkResult(OkLogResult r) {
    if (!mounted) return;
    final taken = _takenByOk;
    setState(() {
      _okResult = r;
      if (r.complete && taken != null) {
        final current =
            _cylinders.any((c) => c.id == _cylinderId) ? _cylinderId : null;
        if (current == taken.cylinderId) _cylinderId = null;
        if (_pressure.text == taken.pressure) _pressure.clear();
        if (_notes.text == taken.notes) _notes.clear();
      }
    });
    // Not awaited: the mix just used may be new to the chips.
    if (r.analysisId != null) unawaited(_loadMixOptions());
  }

  static String? _blankToNull(String s) => s.trim().isEmpty ? null : s;

  /// O2/He usable for a log entry, or null (no data / sensor error).
  ({double o2, double he})? get _usable {
    final o2 = widget.reading?.o2;
    final he = widget.reading?.he ?? 0;
    if (o2 == null || !o2.isFinite || o2 <= 0 || !he.isFinite) return null;
    return (o2: o2, he: he < 0 ? 0.0 : he);
  }

  /// Accepts `,` as decimal separator too (comma-locale keypads).
  static double? _parseDecimal(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t.replaceAll(',', '.'));
  }

  CylinderChoice? _cylinder(String? id) =>
      _cylinders.where((c) => c.id == id).firstOrNull;

  /// A new cylinder sets the role to its default; the diver can flip it.
  void _selectCylinder(String? id) {
    setState(() {
      _cylinderId = id;
      _role = gasRoleForCylinderRole(_cylinder(id)?.role);
    });
  }

  Future<bool> _confirmUnstable() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reading not stable'),
        content: const Text(
            'The analyzer hasn\'t settled yet, so this reading may be off. '
            'Wait for STABLE for an accurate value, or save it anyway '
            '(it will be marked as not stable).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('analysis-save-anyway'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save anyway'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Before printing: on a hard mismatch with the desired mix the label
  /// shows the analysed mix, so the diver confirms first. True to go on.
  /// "Change desired mix" stops and brings the mix chips into view.
  Future<bool> _confirmMix(NewGasAnalysis analysis) async {
    final pending = GasAnalysis.fromNew('pending', analysis);
    if (pending.match?.level != MixMatchLevel.hard) return true;
    final choice = await showMixMismatchDialog(context, analysis: pending);
    if (choice == MismatchChoice.changeMix) {
      final mixRow = _mixKey.currentContext;
      if (mixRow != null && mixRow.mounted) {
        await Scrollable.ensureVisible(
          mixRow,
          duration: const Duration(milliseconds: 300),
        );
      }
    }
    return choice == MismatchChoice.printAnalysed;
  }

  /// "Save analysis", and with [printTo] "Save & print". Confirms an
  /// unstable reading and, before printing, a hard mismatch with the
  /// desired mix; then saves; then prints what was saved. A failed save
  /// prints nothing. A failed print leaves the analysis saved, and its
  /// Retry only prints.
  Future<void> _save({LabelPrintService? printTo}) async {
    final gas = _usable;
    // The guard goes up before the first await, so a second tap while a
    // dialog opens or the save runs can't save the reading twice.
    if (gas == null || _busy) return;
    setState(() => _saving = true);
    try {
      // Snapshot before any await: the reading keeps updating at 1 Hz.
      final reading = widget.reading!;
      final analysis = NewGasAnalysis(
        cylinderId: _cylinderId,
        analysedBy: _diver.text,
        analysedFor: _blankToNull(_for.text),
        analysedAt: widget.now(),
        o2Percent: gas.o2,
        hePercent: gas.he,
        fillPressureBar: _parseDecimal(_pressure.text),
        tempC: reading.tempC != null && reading.tempC!.isFinite
            ? reading.tempC
            : null,
        baroHpa: reading.baroHpa != null && reading.baroHpa!.isFinite
            ? reading.baroHpa
            : null,
        modPpo2s: widget.modPpo2s,
        stable: widget.stability == ReadingStability.stable,
        notes: _notes.text,
        desiredMix: _desired,
        gasRole: _role,
      );
      final copies = _copies;
      final messenger = ScaffoldMessenger.of(context);
      if (!analysis.stable && !await _confirmUnstable()) return;
      if (!mounted) return;
      if (printTo != null && !await _confirmMix(analysis)) return;
      if (!mounted) return;
      final saved = await _add(analysis, messenger);
      if (saved == null || printTo == null || !mounted) return;
      setState(() {
        _saving = false;
        _printing = true;
      });
      // Retry reads the analysis back first: it may have been edited or
      // deleted in the log by then, and this card may be gone.
      final dao = widget.dao;
      // Replaces the "Saved …" SnackBar with how the print went.
      await printWithFeedback(
        context,
        service: printTo,
        analysis: saved,
        copies: copies,
        reload: () async =>
            (await dao.list()).where((x) => x.id == saved.id).firstOrNull,
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _printing = false;
        });
      }
    }
  }

  /// Saves [a] to the log and says so. Returns it as saved, or null when
  /// the save failed (a SnackBar says why, and the diver's choices stay).
  ///
  /// Each result replaces the SnackBar that is up. A print failure from
  /// the previous analysis stays until dismissed (it has a Retry), so a new
  /// bar would queue behind it: a failed save would go unseen, and the old
  /// Retry would still be offered.
  Future<GasAnalysis?> _add(
    NewGasAnalysis a,
    ScaffoldMessengerState messenger,
  ) async {
    final String id;
    try {
      id = await widget.dao.add(a);
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
      return null;
    }
    final saved = GasAnalysis.fromNew(id, a,
        cylinderLabel: _cylinder(a.cylinderId)?.label);
    if (!mounted) return saved;
    // Keep cylinder and diver for the next fill. The per-fill fields clear,
    // and the desired mix, role and copies start over: up to a red match
    // the label prints the desired name, so a mix left picked would label
    // the next cylinder with it. A print still uses [saved] and the copies
    // taken with it, the snapshot. In Log on OK mode they are the setup of
    // the next OK press and stay, as a press that saves them leaves them.
    if (widget.okLogger == null) {
      setState(() {
        _desired = null;
        _role = gasRoleForCylinderRole(_cylinder(_cylinderId)?.role);
        _copies = 1;
      });
    }
    // Not awaited: the print needn't wait for the chips.
    unawaited(_loadMixOptions());
    _pressure.clear();
    _notes.clear();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text('Saved ${gasMixName(a.o2Percent, a.hePercent)} to the '
          'analysis log${a.stable ? '' : ' (not stable)'}.'),
    ));
    return saved;
  }

  /// "Edit" on the result: the sheet on the entry as stored, so changes made
  /// since (a sign-off from the log, a sync) are in it. Signing off here
  /// turns the result into a plain "Saved". Printing after a sign-off is
  /// left to the log, so the sheet does not offer it.
  Future<void> _editResult(OkLogResult r) async {
    final id = r.analysisId;
    if (id == null || _okBusy) return;
    setState(() => _okBusy = true);
    try {
      final messenger = ScaffoldMessenger.of(context);
      final List<GasAnalysis> log;
      try {
        log = await widget.dao.list();
      } catch (e) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
            SnackBar(content: Text('Could not open the analysis: $e')));
        return;
      }
      if (!mounted) return;
      final stored = log.where((x) => x.id == id).firstOrNull;
      if (stored == null) {
        setState(() {
          if (identical(_okResult, r)) _okResult = null;
        });
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
            const SnackBar(content: Text('This analysis was deleted.')));
        return;
      }
      final name = _diver.text.trim();
      final outcome = await showAnalysisEditSheet(
        context,
        dao: widget.dao,
        analysis: stored,
        mixOptions: recentDesiredMixes(log, blendTarget: widget.blendTarget),
        suggestedAnalysedBy: name.isEmpty ? null : name,
      );
      if (!mounted || outcome == AnalysisEditOutcome.cancelled) return;
      messenger.hideCurrentSnackBar();
      if (outcome == AnalysisEditOutcome.deleted) {
        setState(() {
          if (identical(_okResult, r)) _okResult = null;
        });
        messenger.showSnackBar(
          SnackBar(content: Text('Deleted ${stored.mixName} analysis.')),
        );
      } else if (outcome != AnalysisEditOutcome.saved &&
          identical(_okResult, r)) {
        // Signed off: nothing is left to do for this entry.
        setState(() => _okResult = OkLogResult(
              code: FeedbackCode.saved,
              text: stored.mixName,
              analysisId: id,
              complete: true,
            ));
      }
    } finally {
      if (mounted) setState(() => _okBusy = false);
    }
  }

  /// "Delete" on the result: a confirm, then the entry is soft-deleted.
  Future<void> _deleteResult(OkLogResult r) async {
    final id = r.analysisId;
    if (id == null || _okBusy) return;
    setState(() => _okBusy = true);
    try {
      final messenger = ScaffoldMessenger.of(context);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete this analysis?'),
          content: const Text('It is removed from the analysis log.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('analysis-ok-delete-confirm'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await widget.dao.softDelete(id);
      } catch (e) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
        return;
      }
      if (!mounted) return;
      setState(() {
        if (identical(_okResult, r)) _okResult = null;
      });
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('Analysis deleted.')));
    } finally {
      if (mounted) setState(() => _okBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final gas = _usable;
    final usable = gas != null;
    final stable = widget.stability == ReadingStability.stable;
    final desired = _desired;
    final printing = widget.labelPrinting;
    final printReady = _printReady;
    final okMode = widget.okLogger != null;
    final roomAir = gas != null && isRoomAir(gas.o2, gas.he);
    // OK doesn't log air, so the Save buttons stay for it.
    final showSave = !okMode || roomAir;
    // A cylinder deleted elsewhere (sync) drops out of the list; don't
    // leave the dropdown pointing at a value it no longer has.
    final selected = _cylinders.any((c) => c.id == _cylinderId)
        ? _cylinderId
        : null;
    final onSave = usable && !_busy ? () => _save() : null;
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
            key: _mixKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mix (optional)',
                style:
                    AppTypography.caption.copyWith(color: palette.textMuted),
              ),
              const SizedBox(height: Spacing.xs),
              DesiredMixPicker(
                options: _mixOptions,
                selected: desired,
                onChanged: (m) => setState(() => _desired = m),
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
            selected: {_role},
            onSelectionChanged: (s) => setState(() => _role = s.first),
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
              for (final c in _cylinders)
                DropdownMenuItem<String?>(
                  value: c.id,
                  child: Text(c.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _selectCylinder,
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('analysis-diver'),
                  controller: _diver,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Analysed by',
                    isDense: true,
                  ),
                  onChanged: (v) => widget.onAnalysedByChanged
                      ?.call(v.trim().isEmpty ? null : v),
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: TextField(
                  key: const ValueKey('analysis-pressure'),
                  controller: _pressure,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Fill pressure (bar)',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            key: const ValueKey('analysis-for'),
            controller: _for,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'For (optional)',
              isDense: true,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            key: const ValueKey('analysis-notes'),
            controller: _notes,
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
                    !showSave
                        ? 'Reading not stable yet. Wait for STABLE before '
                            'pressing OK.'
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
                      onPressed: usable && !_busy
                          ? () => _save(printTo: printing)
                          : null,
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Save & print'),
                    ),
                    CopiesStepper(
                      value: _copies,
                      onChanged: (v) => setState(() => _copies = v),
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
          if (okMode && _okResult != null) ...[
            const SizedBox(height: Spacing.sm),
            _okResultRow(_okResult!),
          ],
        ],
      ),
    );
  }

  /// "Print label on OK", with the copies while the Save buttons (which
  /// carry their own) are away. Off and disabled without a printer.
  Widget _printOnOkRow({required bool printReady, required bool showCopies}) {
    final on = printReady && (_printOnOk ?? true);
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
              onChanged:
                  printReady ? (v) => setState(() => _printOnOk = v) : null,
            ),
          ),
        ),
        if (on && showCopies)
          CopiesStepper(
            value: _copies,
            onChanged: (v) => setState(() => _copies = v),
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
                onPressed: _okBusy ? null : () => _editResult(r),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
              TextButton.icon(
                key: const ValueKey('analysis-ok-delete'),
                onPressed: _okBusy ? null : () => _deleteResult(r),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
            ],
          ),
      ],
    );
  }
}
