/// Edit sheet for a saved gas analysis (issue #114, #113), opened from the
/// analysis log.
///
/// What the diver states can change: the desired mix, the gas role, who
/// analysed, who the gas is for, the cylinder, the fill pressure and the
/// notes ([GasAnalysisEdit]). The measured values (O2, He, time, stability,
/// temperature) are shown for reference, never as inputs. A reprint after an
/// edit uses the corrected values.
///
/// An entry that needs sign-off (Log on OK) gets a "Sign off" button, which
/// needs "analysed by" and a desired mix, and, with a printer set up, "Sign
/// off and print". The sheet can also delete the entry, after a confirm.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../analysis/fill_pressure.dart';
import '../../data/db/gas_analyses_dao.dart';
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';
import 'desired_mix_picker.dart';
import 'mix_match_indicator.dart';

/// How the edit sheet closed.
enum AnalysisEditOutcome {
  /// Closed with nothing written: Cancel, or dismissed.
  cancelled,

  /// The edit was saved. An entry that needed sign-off still does.
  saved,

  /// The edit was saved and the entry signed off.
  signedOff,

  /// The edit was saved and the entry signed off; the caller prints its
  /// label ("Sign off and print").
  signOffAndPrint,

  /// The entry was deleted.
  deleted,
}

/// Opens the edit sheet for [analysis]. [mixOptions] are the desired mixes
/// to offer as chips and must not hold the same mix twice (see
/// [DesiredMixPicker]).
///
/// [suggestedAnalysedBy] starts the "Analysed by" field when the entry has
/// no name. With [canPrint], an entry that needs sign-off also offers "Sign
/// off and print"; the sheet only signs off and returns
/// [AnalysisEditOutcome.signOffAndPrint], the caller prints.
///
/// Returns what was done. A write that fails keeps the sheet open and says
/// why.
Future<AnalysisEditOutcome> showAnalysisEditSheet(
  BuildContext context, {
  required GasAnalysesDaoLike dao,
  required GasAnalysis analysis,
  required List<DesiredMix> mixOptions,
  String? suggestedAnalysedBy,
  bool canPrint = false,
}) async {
  // Set by the sheet once its write has gone through, just before it closes
  // itself. A sheet dismissed while that write is still running returns
  // cancelled, even if the write then succeeds: the change is stored, and
  // the log, which watches the DAO, still shows it, but a caller that acts
  // on the outcome (a reprint after "Change desired mix") stops instead.
  var outcome = AnalysisEditOutcome.cancelled;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AnalysisEditSheet(
      dao: dao,
      analysis: analysis,
      mixOptions: mixOptions,
      suggestedAnalysedBy: suggestedAnalysedBy,
      canPrint: canPrint,
      onDone: (o) => outcome = o,
    ),
  );
  return outcome;
}

class _AnalysisEditSheet extends StatefulWidget {
  const _AnalysisEditSheet({
    required this.dao,
    required this.analysis,
    required this.mixOptions,
    required this.suggestedAnalysedBy,
    required this.canPrint,
    required this.onDone,
  });

  final GasAnalysesDaoLike dao;
  final GasAnalysis analysis;
  final List<DesiredMix> mixOptions;
  final String? suggestedAnalysedBy;
  final bool canPrint;
  final ValueChanged<AnalysisEditOutcome> onDone;

  @override
  State<_AnalysisEditSheet> createState() => _AnalysisEditSheetState();
}

class _AnalysisEditSheetState extends State<_AnalysisEditSheet> {
  late DesiredMix? _desired = widget.analysis.desiredMix;
  late GasRole _role = widget.analysis.gasRole;
  late String? _cylinderId = widget.analysis.cylinderId;
  // The suggestion is for the entry that is waiting for a sign-off. An old
  // entry that was saved without a name stays without one: Save must not put
  // today's name on it.
  late final _diver = TextEditingController(
      text: _blankToNull(widget.analysis.analysedBy ?? '') ??
          (widget.analysis.needsSignoff ? widget.suggestedAnalysedBy : null) ??
          '');
  late final _fill = TextEditingController(
      text: _pressureText(widget.analysis.fillPressureBar));
  late final _forWhom =
      TextEditingController(text: widget.analysis.analysedFor ?? '');
  late final _notes = TextEditingController(text: widget.analysis.notes ?? '');

  /// The diver's cylinders, once read. Until then, and if the read fails,
  /// the entry's own cylinder is still offered (see [_cylinderItems]).
  List<CylinderChoice> _cylinders = const [];

  /// A write (save, sign off, delete) is under way, or the delete dialog is
  /// up; a second tap on any of the buttons does nothing.
  bool _saving = false;

  /// Why the last write failed, shown above the buttons.
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCylinders();
  }

  @override
  void dispose() {
    _diver.dispose();
    _fill.dispose();
    _forWhom.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadCylinders() async {
    final List<CylinderChoice> list;
    try {
      list = await widget.dao.listCylinderChoices();
    } catch (e) {
      debugPrint('Analysis edit sheet: loading the cylinders failed: $e');
      return;
    }
    if (!mounted) return;
    setState(() => _cylinders = list);
  }

  /// Trimmed, and null when blank. The DAO does the same; doing it here
  /// keeps the edit the sheet hands over equal to what gets stored.
  static String? _blankToNull(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  /// The fill pressure as typed into the field: whole bar without a
  /// decimal point.
  static String _pressureText(double? bar) {
    if (bar == null || !bar.isFinite) return '';
    return bar == bar.roundToDouble() ? bar.toStringAsFixed(0) : bar.toString();
  }

  /// "No cylinder", the entry's own cylinder when it is not one of the
  /// diver's (deleted in Equipment, or not known on this device), then the
  /// diver's cylinders. Keeping the entry's own as an item means an edit of
  /// something else never drops the link.
  List<DropdownMenuItem<String?>> _cylinderItems() {
    final own = widget.analysis.cylinderId;
    final ownKnown = _cylinders.any((c) => c.id == own);
    return [
      const DropdownMenuItem<String?>(value: null, child: Text('No cylinder')),
      if (own != null && !ownKnown)
        DropdownMenuItem<String?>(
          value: own,
          child: Text(widget.analysis.cylinderDisplay!,
              overflow: TextOverflow.ellipsis),
        ),
      for (final c in _cylinders)
        DropdownMenuItem<String?>(
          value: c.id,
          child: Text(c.label, overflow: TextOverflow.ellipsis),
        ),
    ];
  }

  /// A cylinder of the diver's sets the role to its default. With no
  /// desired mix picked, the desired mix and role of that cylinder's latest
  /// other analysis follow: the re-check case, compared against what the
  /// diver thought was in the cylinder. "No cylinder" and a cylinder that
  /// is not in Equipment say nothing, so the role stays.
  void _selectCylinder(String? id) {
    if (id == _cylinderId) return;
    final choice = _cylinders.where((c) => c.id == id).firstOrNull;
    setState(() {
      _cylinderId = id;
      if (choice != null) _role = gasRoleForCylinderRole(choice.role);
    });
    if (choice != null && _desired == null) unawaited(_takeLatestMix(id!));
  }

  Future<void> _takeLatestMix(String cylinderId) async {
    final List<GasAnalysis> list;
    try {
      list = await widget.dao.list(cylinderId: cylinderId);
    } catch (e) {
      debugPrint('Analysis edit sheet: reading the cylinder\'s analyses '
          'failed: $e');
      return;
    }
    // The diver may have picked a mix or another cylinder meanwhile.
    if (!mounted || _cylinderId != cylinderId || _desired != null) return;
    // Newest first; not this entry itself.
    final latest = list
        .where((a) => a.id != widget.analysis.id && a.desiredMix != null)
        .firstOrNull;
    if (latest == null) return;
    setState(() {
      _desired = latest.desiredMix;
      _role = latest.gasRole;
    });
  }

  /// Writes the edit and closes with [outcome]: saved, signedOff or
  /// signOffAndPrint.
  Future<void> _write(AnalysisEditOutcome outcome) async {
    // The guard goes up before the first await, so a double tap can't
    // write the edit twice.
    if (_saving) return;
    final pressure = parseFillPressure(_fill.text);
    if (!pressure.valid) return;
    final signOff = outcome == AnalysisEditOutcome.signedOff ||
        outcome == AnalysisEditOutcome.signOffAndPrint;
    final analysedBy = _blankToNull(_diver.text);
    if (signOff && (analysedBy == null || _desired == null)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    final onDone = widget.onDone;
    try {
      await widget.dao.update(
        widget.analysis.id,
        GasAnalysisEdit(
          desiredMix: _desired,
          gasRole: _role,
          analysedBy: analysedBy,
          notes: _blankToNull(_notes.text),
          cylinderId: _cylinderId,
          fillPressureBar: pressure.bar,
          analysedFor: _blankToNull(_forWhom.text),
          signOff: signOff,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Save failed: $e';
      });
      return;
    }
    onDone(outcome);
    _closeIfOpen(navigator, route);
  }

  /// Closes the sheet after a write, unless it is already closing. A sheet
  /// dismissed while its write was under way is still mounted for the length
  /// of its exit animation; a pop then would close the route underneath (the
  /// analyzer screen, which stops Log on OK).
  void _closeIfOpen(NavigatorState navigator, ModalRoute<dynamic>? route) {
    if (mounted && (route == null || route.isCurrent)) navigator.pop();
  }

  /// Asks, then soft-deletes the entry and closes. The guard stays up while
  /// the dialog is open, so a second tap can't open a second one.
  Future<void> _delete() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    final onDone = widget.onDone;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this analysis?'),
        content: Text('${widget.analysis.mixName} is removed from the log.'),
        actions: [
          TextButton(
            key: const ValueKey('analysis-delete-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('analysis-delete-confirm'),
            style: TextButton.styleFrom(foregroundColor: SafetyColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    try {
      await widget.dao.softDelete(widget.analysis.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Delete failed: $e';
      });
      return;
    }
    onDone(AnalysisEditOutcome.deleted);
    _closeIfOpen(navigator, route);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final a = widget.analysis;
    final desired = _desired;
    final error = _error;
    final flagged = a.needsSignoff;
    final pressure = parseFillPressure(_fill.text);
    final hasName = _blankToNull(_diver.text) != null;
    final canWrite = !_saving && pressure.valid;
    final canSignOff = canWrite && hasName && desired != null;
    return Padding(
      key: const ValueKey('analysis-edit-sheet'),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Edit analysis',
              style:
                  AppTypography.headline.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(height: Spacing.md),
            _MeasuredValues(analysis: a),
            const SizedBox(height: Spacing.lg),
            Text(
              'Mix (optional)',
              style: AppTypography.caption.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: Spacing.xs),
            DesiredMixPicker(
              options: widget.mixOptions,
              selected: desired,
              onChanged: (m) => setState(() => _desired = m),
            ),
            // Grading NaN throws; a stored analysis is finite, but a row
            // from elsewhere is not worth a crash.
            if (desired != null &&
                a.o2Percent.isFinite &&
                a.hePercent.isFinite) ...[
              const SizedBox(height: Spacing.sm),
              MixMatchIndicator(
                o2Percent: a.o2Percent,
                hePercent: a.hePercent,
                desired: desired,
              ),
            ],
            const SizedBox(height: Spacing.md),
            SegmentedButton<GasRole>(
              key: const ValueKey('analysis-edit-role'),
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
              key: const ValueKey('analysis-edit-cylinder'),
              initialValue: _cylinderId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Cylinder (optional)',
                isDense: true,
              ),
              items: _cylinderItems(),
              onChanged: _selectCylinder,
            ),
            const SizedBox(height: Spacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('analysis-edit-diver'),
                    controller: _diver,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Analysed by',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: TextField(
                    key: const ValueKey('analysis-edit-pressure'),
                    controller: _fill,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Fill pressure (bar)',
                      isDense: true,
                      errorText:
                          pressure.valid ? null : 'Enter a pressure in bar',
                      errorMaxLines: 2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              key: const ValueKey('analysis-edit-for'),
              controller: _forWhom,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'For (optional)',
                hintText: 'Who the gas is for',
                isDense: true,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              key: const ValueKey('analysis-edit-notes'),
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Notes',
                isDense: true,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                error,
                key: const ValueKey('analysis-edit-error'),
                style: AppTypography.body.copyWith(color: SafetyColors.danger),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            if (flagged) ...[
              if (!hasName || desired == null) ...[
                Text(
                  'To sign off, add who analysed it and the desired mix.',
                  key: const ValueKey('analysis-edit-signoff-hint'),
                  style:
                      AppTypography.caption.copyWith(color: palette.textMuted),
                ),
                const SizedBox(height: Spacing.sm),
              ],
              FilledButton(
                key: const ValueKey('analysis-edit-signoff'),
                onPressed: canSignOff
                    ? () => _write(AnalysisEditOutcome.signedOff)
                    : null,
                child: const Text('Sign off'),
              ),
              if (widget.canPrint) ...[
                const SizedBox(height: Spacing.sm),
                OutlinedButton(
                  key: const ValueKey('analysis-edit-signoff-print'),
                  onPressed: canSignOff
                      ? () => _write(AnalysisEditOutcome.signOffAndPrint)
                      : null,
                  child: const Text('Sign off and print'),
                ),
              ],
              const SizedBox(height: Spacing.sm),
            ],
            Row(
              children: [
                TextButton(
                  key: const ValueKey('analysis-edit-delete'),
                  style: TextButton.styleFrom(
                      foregroundColor: SafetyColors.danger),
                  onPressed: _saving ? null : _delete,
                  child: const Text('Delete'),
                ),
                // Cancel and Save stack when a narrow phone or a large font
                // leaves no room for both beside Delete.
                Expanded(
                  child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    overflowAlignment: OverflowBarAlignment.end,
                    spacing: Spacing.sm,
                    children: [
                      TextButton(
                        key: const ValueKey('analysis-edit-cancel'),
                        onPressed:
                            _saving ? null : () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      // On a flagged entry Save keeps the flag, so Sign off
                      // is the primary button there.
                      if (flagged)
                        OutlinedButton(
                          key: const ValueKey('analysis-edit-save'),
                          onPressed: canWrite
                              ? () => _write(AnalysisEditOutcome.saved)
                              : null,
                          child: const Text('Save'),
                        )
                      else
                        FilledButton(
                          key: const ValueKey('analysis-edit-save'),
                          onPressed: canWrite
                              ? () => _write(AnalysisEditOutcome.saved)
                              : null,
                          child: const Text('Save'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// What was measured, as text: never an input. The cylinder and the fill
/// pressure are stated, not measured: they are inputs of the sheet.
class _MeasuredValues extends StatelessWidget {
  const _MeasuredValues({required this.analysis});

  final GasAnalysis analysis;

  static final _dateFormat = DateFormat('d MMM yyyy, HH:mm');

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final a = analysis;
    final stableColor = a.stable ? SafetyColors.success : SafetyColors.warning;
    final details = <String>[
      _dateFormat.format(a.analysedAt),
      if (a.tempC != null) '${a.tempC!.toStringAsFixed(1)} °C',
    ];
    return Container(
      key: const ValueKey('analysis-edit-measured'),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: palette.surfaceRaised),
        borderRadius: Radii.cardBr,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  a.mixName,
                  style:
                      AppTypography.title.copyWith(color: palette.textPrimary),
                ),
              ),
              Icon(
                a.stable ? Icons.check_circle : Icons.warning_amber_rounded,
                size: 16,
                color: stableColor,
              ),
              const SizedBox(width: Spacing.xs),
              Text(
                a.stable ? 'Stable' : 'Not stable',
                style: AppTypography.label.copyWith(color: stableColor),
              ),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            'O2 ${a.o2Percent.toStringAsFixed(1)} %   '
            'He ${a.hePercent.toStringAsFixed(1)} %',
            style: AppTypography.readoutSm.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            details.join(' · '),
            style: AppTypography.body.copyWith(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}
