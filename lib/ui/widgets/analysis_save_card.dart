/// "Save analysis" card on the gas-analyzer screen (issue #111).
///
/// Captures the current reading plus the diver's context (cylinder from
/// Equipment, who analysed, fill pressure, notes) into the synced
/// cylinder analysis log. A reading that isn't STABLE asks for
/// confirmation first; it's never blocked, because a diver at the fill
/// station sometimes has to log what they've got.
library;

import 'package:flutter/material.dart';

import '../../analysis/gas_naming.dart';
import '../../analyzer/protocol/analyzer_reading.dart';
import '../../analyzer/stability.dart';
import '../../data/db/gas_analyses_dao.dart';
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';

class AnalysisSaveCard extends StatefulWidget {
  const AnalysisSaveCard({
    super.key,
    required this.dao,
    required this.reading,
    required this.stability,
    required this.modPpo2s,
    this.now = DateTime.now,
  });

  final GasAnalysesDaoLike dao;

  /// The live reading to save; null before the first one.
  final AnalyzerReading? reading;
  final ReadingStability stability;

  /// The ppO2 set the screen shows MODs for; stored with the analysis.
  final List<double> modPpo2s;

  /// Clock, injectable for tests.
  final DateTime Function() now;

  @override
  State<AnalysisSaveCard> createState() => _AnalysisSaveCardState();
}

class _AnalysisSaveCardState extends State<AnalysisSaveCard> {
  final _diver = TextEditingController();
  final _pressure = TextEditingController();
  final _notes = TextEditingController();
  List<CylinderChoice> _cylinders = const [];
  String? _cylinderId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCylinders();
  }

  Future<void> _loadCylinders() async {
    final list = await widget.dao.listCylinderChoices();
    if (!mounted) return;
    setState(() => _cylinders = list);
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

  Future<void> _save() async {
    final gas = _usable;
    if (gas == null || _saving) return;
    // Snapshot before any await: the reading keeps updating at 1 Hz.
    final reading = widget.reading!;
    final stable = widget.stability == ReadingStability.stable;
    final analysedAt = widget.now();
    final messenger = ScaffoldMessenger.of(context);
    if (!stable && !await _confirmUnstable()) return;
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await widget.dao.add(NewGasAnalysis(
        cylinderId: _cylinderId,
        analysedBy: _diver.text,
        analysedAt: analysedAt,
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
        stable: stable,
        notes: _notes.text,
      ));
      if (!mounted) return;
      // Keep cylinder + diver for the next fill; clear the per-fill fields.
      _pressure.clear();
      _notes.clear();
      messenger.showSnackBar(SnackBar(
        content: Text('Saved ${gasMixName(gas.o2, gas.he)} to the '
            'analysis log${stable ? '' : ' (not stable)'}.'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final usable = _usable != null;
    final stable = widget.stability == ReadingStability.stable;
    // A cylinder deleted elsewhere (sync) drops out of the list; don't
    // leave the dropdown pointing at a value it no longer has.
    final selected = _cylinders.any((c) => c.id == _cylinderId)
        ? _cylinderId
        : null;
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
            onChanged: (v) => setState(() => _cylinderId = v),
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
          FilledButton.icon(
            key: const ValueKey('analysis-save'),
            onPressed: usable && !_saving ? _save : null,
            icon: const Icon(Icons.save_alt),
            label: const Text('Save analysis'),
          ),
        ],
      ),
    );
  }
}
