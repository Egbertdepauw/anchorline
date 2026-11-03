/// Edit sheet for a saved gas analysis (issue #114), opened from the
/// analysis log.
///
/// Only what the diver states can change: the desired mix, the gas role,
/// who analysed and the notes ([GasAnalysisEdit]). The measured values (O2,
/// He, time, stability, fill pressure, temperature) and the cylinder are
/// shown for reference, never as inputs. A reprint after an edit uses the
/// corrected values.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/db/gas_analyses_dao.dart';
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';
import 'desired_mix_picker.dart';
import 'mix_match_indicator.dart';

/// Opens the edit sheet for [analysis]. [mixOptions] are the desired mixes
/// to offer as chips and must not hold the same mix twice (see
/// [DesiredMixPicker]).
///
/// Returns true when the edit was saved, false when the sheet was cancelled
/// or dismissed. A save that fails keeps the sheet open and says why.
Future<bool> showAnalysisEditSheet(
  BuildContext context, {
  required GasAnalysesDaoLike dao,
  required GasAnalysis analysis,
  required List<DesiredMix> mixOptions,
}) async {
  // Set by the sheet once its update has gone through, just before it
  // closes itself. A sheet dismissed while that update is still running
  // returns false, even if the update then succeeds: the edit is stored,
  // and the log, which watches the DAO, still shows it, but a caller that
  // acts on true (a reprint after "Change desired mix") stops instead.
  var saved = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AnalysisEditSheet(
      dao: dao,
      analysis: analysis,
      mixOptions: mixOptions,
      onSaved: () => saved = true,
    ),
  );
  return saved;
}

class _AnalysisEditSheet extends StatefulWidget {
  const _AnalysisEditSheet({
    required this.dao,
    required this.analysis,
    required this.mixOptions,
    required this.onSaved,
  });

  final GasAnalysesDaoLike dao;
  final GasAnalysis analysis;
  final List<DesiredMix> mixOptions;
  final VoidCallback onSaved;

  @override
  State<_AnalysisEditSheet> createState() => _AnalysisEditSheetState();
}

class _AnalysisEditSheetState extends State<_AnalysisEditSheet> {
  late DesiredMix? _desired = widget.analysis.desiredMix;
  late GasRole _role = widget.analysis.gasRole;
  late final _diver =
      TextEditingController(text: widget.analysis.analysedBy ?? '');
  late final _notes = TextEditingController(text: widget.analysis.notes ?? '');

  /// The update is under way; a second tap on Save does nothing.
  bool _saving = false;

  /// Why the last save failed, shown above the buttons.
  String? _error;

  @override
  void dispose() {
    _diver.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Trimmed, and null when blank. The DAO does the same; doing it here
  /// keeps the edit the sheet hands over equal to what gets stored.
  static String? _blankToNull(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _save() async {
    // The guard goes up before the first await, so a double tap can't
    // write the edit twice.
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final onSaved = widget.onSaved;
    try {
      await widget.dao.update(
        widget.analysis.id,
        GasAnalysisEdit(
          desiredMix: _desired,
          gasRole: _role,
          analysedBy: _blankToNull(_diver.text),
          notes: _blankToNull(_notes.text),
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
    onSaved();
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final a = widget.analysis;
    final desired = _desired;
    final error = _error;
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
            TextField(
              key: const ValueKey('analysis-edit-diver'),
              controller: _diver,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Analysed by',
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
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const ValueKey('analysis-edit-cancel'),
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: Spacing.sm),
                FilledButton(
                  key: const ValueKey('analysis-edit-save'),
                  onPressed: _saving ? null : _save,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// What was measured, as text: never an input.
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
      if (a.cylinderDisplay != null) a.cylinderDisplay!,
      if (a.fillPressureBar != null)
        '${a.fillPressureBar!.toStringAsFixed(0)} bar',
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
