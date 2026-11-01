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
library;

import 'package:flutter/material.dart';

import '../../analysis/gas_naming.dart';
import '../../analysis/mix_match.dart';
import '../../analyzer/protocol/analyzer_reading.dart';
import '../../analyzer/stability.dart';
import '../../data/db/gas_analyses_dao.dart';
import '../../labels/label_print_service.dart';
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';
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

  /// Clock, injectable for tests.
  final DateTime Function() now;

  @override
  State<AnalysisSaveCard> createState() => _AnalysisSaveCardState();
}

class _AnalysisSaveCardState extends State<AnalysisSaveCard> {
  final _diver = TextEditingController();
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

  @override
  void initState() {
    super.initState();
    _loadChoices();
  }

  /// The cylinders to pick from and the desired mixes to offer.
  Future<void> _loadChoices() async {
    final cylinders = await widget.dao.listCylinderChoices();
    final log = await widget.dao.list();
    if (!mounted) return;
    setState(() {
      _cylinders = cylinders;
      _mixOptions = recentDesiredMixes(log, blendTarget: widget.blendTarget);
    });
  }

  @override
  void dispose() {
    _diver.dispose();
    _pressure.dispose();
    _notes.dispose();
    super.dispose();
  }

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
      // Replaces the "Saved …" SnackBar with how the print went.
      await printWithFeedback(
        context,
        service: printTo,
        analysis: saved,
        copies: copies,
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
  /// the save failed (a SnackBar says why).
  Future<GasAnalysis?> _add(
    NewGasAnalysis a,
    ScaffoldMessengerState messenger,
  ) async {
    final String id;
    try {
      id = await widget.dao.add(a);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
      return null;
    }
    final saved = GasAnalysis.fromNew(id, a,
        cylinderLabel: _cylinder(a.cylinderId)?.label);
    if (!mounted) return saved;
    // Keep cylinder, diver, mix and role for the next fill; clear the
    // per-fill fields.
    _pressure.clear();
    _notes.clear();
    messenger.showSnackBar(SnackBar(
      content: Text('Saved ${gasMixName(a.o2Percent, a.hePercent)} to the '
          'analysis log${a.stable ? '' : ' (not stable)'}.'),
    ));
    return saved;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final gas = _usable;
    final usable = gas != null;
    final stable = widget.stability == ReadingStability.stable;
    final desired = _desired;
    final printing = widget.labelPrinting;
    final printReady = printing != null && printing.isConfigured;
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
                    'Reading not stable yet. Wait for STABLE before saving.',
                    style: AppTypography.caption
                        .copyWith(color: SafetyColors.warning),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
          ],
          if (!printReady)
            FilledButton.icon(
              key: const ValueKey('analysis-save'),
              onPressed: onSave,
              icon: saveIcon,
              label: saveLabel,
            )
          else
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
        ],
      ),
    );
  }
}
