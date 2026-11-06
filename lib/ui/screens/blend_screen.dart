/// Gas Blend screen — partial-pressure blending planner.
///
/// Input cards (current cylinder / target / top-off) on top, output
/// card with the ordered fill plan + cost + final-mix readouts on the
/// bottom. Same wreck-palette aesthetic as the Dive Plan screen, with
/// accent-bar cards grouping the inputs by responsibility.
///
/// Settings → "Gas blending" carries the per-litre prices, default
/// top-off, default fill sequence, and ideal-gas vs real-gas toggle.
library;

import 'package:flutter/material.dart';

import '../../analysis/blending/gas_blender.dart';
import '../../data/db/gas_analyses_dao.dart';
import '../../labels/label_print_service.dart';
import '../notifiers/analyzer_session.dart';
import '../notifiers/blend_notifier.dart';
import '../notifiers/settings_notifier.dart';
import 'analyzer_screen.dart';
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';
import '../../analysis/gas_naming.dart';

class BlendScreen extends StatefulWidget {
  const BlendScreen({
    super.key,
    required this.notifier,
    required this.settings,
    required this.analyzerSession,
    this.analysesDao,
    this.labelPrinting,
  });

  final BlendNotifier notifier;
  final SettingsNotifier settings;

  /// The analyzer connection, handed to the analyzer screen.
  final AnalyzerSession analyzerSession;

  /// Cylinder analysis log (#111), handed to the analyzer screen.
  final GasAnalysesDaoLike? analysesDao;

  /// Cylinder label printing (#114), handed to the analyzer screen.
  final LabelPrintService? labelPrinting;

  @override
  State<BlendScreen> createState() => _BlendScreenState();
}

class _BlendScreenState extends State<BlendScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blend'),
        actions: [
          // Labelled, not icon-only: a bare icon didn't read as
          // "open the gas analyzer" to testers.
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              key: const Key('blend-open-analyzer'),
              icon: const Icon(Icons.science_outlined),
              label: const Text('Analyze gas'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AnalyzerScreen(
                    settings: widget.settings,
                    session: widget.analyzerSession,
                    analysesDao: widget.analysesDao,
                    // Read when the analyzer opens: the mix being blended
                    // now, if the diver used the Blend tab recently.
                    blendTarget: widget.notifier.recentTarget(),
                    labelPrinting: widget.labelPrinting,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      // Tap anywhere outside an input field to dismiss the keyboard.
      // iOS's numeric keyboard has no Return key, so without this the
      // user can't get the keyboard out of the way to reach the bottom
      // nav. `translucent` makes hit-testing still pass through to
      // children (cards / chips / dropdowns / switch).
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListenableBuilder(
          listenable: widget.notifier,
          builder: (context, _) => SingleChildScrollView(
            // Dragging the content also dismisses — second escape hatch
            // for users who don't think to tap outside.
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.md, Spacing.md, Spacing.xl),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Card(
                accent: SafetyColors.info,
                label: 'CURRENT CYLINDER',
                child: _CylinderInputs(
                  o2: widget.notifier.currentOxygenPercent,
                  he: widget.notifier.currentHeliumPercent,
                  pressureBar: widget.notifier.currentPressureBar,
                  capacityL: widget.notifier.waterCapacityL,
                  onMixChange: widget.notifier.setCurrentMix,
                  onPressureChange: widget.notifier.setCurrentPressure,
                  onCapacityChange: widget.notifier.setWaterCapacity,
                  showCapacity: true,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              _Card(
                accent: context.palette.cell1,
                label: 'TARGET',
                child: _CylinderInputs(
                  o2: widget.notifier.targetOxygenPercent,
                  he: widget.notifier.targetHeliumPercent,
                  pressureBar: widget.notifier.targetPressureBar,
                  capacityL: widget.notifier.waterCapacityL,
                  onMixChange: widget.notifier.setTargetMix,
                  onPressureChange: widget.notifier.setTargetPressure,
                  onCapacityChange: (_) {},
                  showCapacity: false,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              _Card(
                accent: context.palette.cell2,
                label: 'TOP-OFF',
                child: _TopoffControls(
                  o2: widget.notifier.topoffOxygenPercent,
                  he: widget.notifier.topoffHeliumPercent,
                  sequence: widget.notifier.sequence,
                  useRealGas: widget.notifier.useRealGas,
                  fillTempC: widget.notifier.fillTempC,
                  settledTempC: widget.notifier.settledTempC,
                  onMixChange: widget.notifier.setTopoff,
                  onSequenceChange: widget.notifier.setSequence,
                  onUseRealGasChange: widget.notifier.setUseRealGas,
                  onFillTempChange: widget.notifier.setFillTempC,
                  onSettledTempChange: widget.notifier.setSettledTempC,
                ),
              ),
              const SizedBox(height: Spacing.md),
              _Card(
                accent: context.palette.accentPrimary,
                label: 'FILL PLAN',
                child: _BlendOutput(result: widget.notifier.result),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

// ── Cylinder inputs ───────────────────────────────────────────────────

class _CylinderInputs extends StatelessWidget {
  const _CylinderInputs({
    required this.o2,
    required this.he,
    required this.pressureBar,
    required this.capacityL,
    required this.onMixChange,
    required this.onPressureChange,
    required this.onCapacityChange,
    required this.showCapacity,
  });

  final int o2;
  final int he;
  final double pressureBar;
  final double capacityL;
  final void Function(int o2, int he) onMixChange;
  final ValueChanged<double> onPressureChange;
  final ValueChanged<double> onCapacityChange;
  final bool showCapacity;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _IntField(
              key: ValueKey('${showCapacity ? "cur" : "tgt"}-o2'),
              label: 'O₂',
              value: o2,
              suffix: '%',
              onChanged: (v) => onMixChange(v, he),
              width: 80,
            ),
            const SizedBox(width: Spacing.sm),
            _IntField(
              key: ValueKey('${showCapacity ? "cur" : "tgt"}-he'),
              label: 'He',
              value: he,
              suffix: '%',
              onChanged: (v) => onMixChange(o2, v),
              width: 80,
            ),
            const SizedBox(width: Spacing.sm),
            _DoubleField(
              key: ValueKey('${showCapacity ? "cur" : "tgt"}-pressure'),
              label: 'Pressure',
              value: pressureBar,
              suffix: 'bar',
              onChanged: onPressureChange,
              width: 110,
            ),
          ],
        ),
        if (showCapacity) ...[
          const SizedBox(height: Spacing.sm),
          _DoubleField(
            key: const ValueKey('cur-capacity'),
            label: 'Water capacity',
            value: capacityL,
            suffix: 'L',
            onChanged: onCapacityChange,
            width: 140,
          ),
        ],
      ],
    );
  }
}

// ── Top-off + sequence + real-gas controls ───────────────────────────

class _TopoffControls extends StatelessWidget {
  const _TopoffControls({
    required this.o2,
    required this.he,
    required this.sequence,
    required this.useRealGas,
    required this.fillTempC,
    required this.settledTempC,
    required this.onMixChange,
    required this.onSequenceChange,
    required this.onUseRealGasChange,
    required this.onFillTempChange,
    required this.onSettledTempChange,
  });

  final int o2;
  final int he;
  final FillSequence sequence;
  final bool useRealGas;
  final double fillTempC;
  final double settledTempC;
  final void Function(int o2, int he) onMixChange;
  final ValueChanged<FillSequence> onSequenceChange;
  final ValueChanged<bool> onUseRealGasChange;
  final ValueChanged<double> onFillTempChange;
  final ValueChanged<double> onSettledTempChange;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _IntField(
              key: const ValueKey('topoff-o2'),
              label: 'O₂',
              value: o2,
              suffix: '%',
              onChanged: (v) => onMixChange(v, he),
              width: 80,
            ),
            const SizedBox(width: Spacing.sm),
            _IntField(
              key: const ValueKey('topoff-he'),
              label: 'He',
              value: he,
              suffix: '%',
              onChanged: (v) => onMixChange(o2, v),
              width: 80,
            ),
            const SizedBox(width: Spacing.sm),
            // Quick-pick chips for common top-offs.
            Wrap(
              spacing: 6,
              children: [
                _TopoffChip(
                    label: 'Air',
                    selected: o2 == 21 && he == 0,
                    onTap: () => onMixChange(21, 0)),
                _TopoffChip(
                    label: 'EAN32',
                    selected: o2 == 32 && he == 0,
                    onTap: () => onMixChange(32, 0)),
                _TopoffChip(
                    label: 'EAN50',
                    selected: o2 == 50 && he == 0,
                    onTap: () => onMixChange(50, 0)),
              ],
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        Row(
          children: [
            const SizedBox(
              width: 100,
              child: Text('Fill order', style: AppTypography.caption),
            ),
            Expanded(
              child: DropdownButton<FillSequence>(
                value: sequence,
                isDense: true,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(
                    value: FillSequence.heThenO2ThenTopoff,
                    child: Text('He → O₂ → top-off'),
                  ),
                  DropdownMenuItem(
                    value: FillSequence.o2ThenHeThenTopoff,
                    child: Text('O₂ → He → top-off'),
                  ),
                  DropdownMenuItem(
                    value: FillSequence.o2ThenTopoffThenHe,
                    child: Text('O₂ → top-off → He'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) onSequenceChange(v);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const SizedBox(
              width: 100,
              child: Text('Real gas (Z)', style: AppTypography.caption),
            ),
            Switch.adaptive(
              key: const ValueKey('use-real-gas'),
              value: useRealGas,
              onChanged: onUseRealGasChange,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _DoubleField(
              key: const ValueKey('fill-temp'),
              label: 'Fill temp',
              value: fillTempC,
              suffix: '°C',
              onChanged: onFillTempChange,
              width: 110,
            ),
            const SizedBox(width: Spacing.sm),
            _DoubleField(
              key: const ValueKey('settled-temp'),
              label: 'Settled temp',
              value: settledTempC,
              suffix: '°C',
              onChanged: onSettledTempChange,
              width: 130,
            ),
          ],
        ),
      ],
    );
  }
}

class _TopoffChip extends StatelessWidget {
  const _TopoffChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.chipBr,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: Radii.chipBr,
          color: selected
              ? context.palette.accentPrimary.withValues(alpha: 0.18)
              : context.palette.surfaceRaised,
          border: Border.all(
            color: selected
                ? context.palette.accentPrimary
                : context.palette.surfaceBezel,
          ),
        ),
        child: Text(label, style: AppTypography.caption),
      ),
    );
  }
}

// ── Output (fill plan + cost) ────────────────────────────────────────

class _BlendOutput extends StatelessWidget {
  const _BlendOutput({required this.result});
  final BlendResult? result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r == null || r.steps.isEmpty && r.isOk) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Spacing.sm),
        child: Text(
          'Nothing to do — current contents already match the target.',
          style: AppTypography.caption,
        ),
      );
    }
    if (!r.isOk) {
      return Container(
        padding: const EdgeInsets.all(Spacing.sm + 2),
        decoration: BoxDecoration(
          color: SafetyColors.danger.withValues(alpha: 0.12),
          borderRadius: Radii.cardBr,
          border: Border(
            left: BorderSide(color: SafetyColors.danger, width: 3),
          ),
        ),
        child: Text(
          r.errorMessage ?? 'Impossible blend.',
          style: AppTypography.caption,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (r.drainToPressureBar != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.xs),
            child: Container(
              padding: const EdgeInsets.all(Spacing.sm),
              decoration: BoxDecoration(
                color: SafetyColors.warning.withValues(alpha: 0.12),
                borderRadius: Radii.cardBr,
                border: Border(
                  left: BorderSide(
                      color: SafetyColors.warning, width: 3),
                ),
              ),
              child: Text(
                'Drain to ${r.drainToPressureBar!.toStringAsFixed(0)} bar '
                'first — current contents have more of one gas than the '
                'target needs.',
                style: AppTypography.caption,
              ),
            ),
          ),
        for (final step in r.steps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Container(
                  width: 80,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _verbForStep(step),
                    style: AppTypography.label.copyWith(
                      color: _colorForStep(step, context.palette),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    _detailForStep(step),
                    style: AppTypography.readoutSm,
                  ),
                ),
                Text(
                  '→ ${step.cumulativePressureBar.toStringAsFixed(0)} bar',
                  style: AppTypography.readoutSm.copyWith(
                    color: context.palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        // Hot-fill compensation banner: shown when fill temp ≠ settled
        // so the diver knows the gauge will drop after cooldown.
        if (r.settledPressureBar != null &&
            r.settledTemperatureKelvin != null) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Spacing.sm, vertical: Spacing.xs),
            decoration: BoxDecoration(
              color: SafetyColors.info.withValues(alpha: 0.12),
              borderRadius: Radii.cardBr,
              border: Border(
                left: BorderSide(color: SafetyColors.info, width: 3),
              ),
            ),
            child: Text(
              'Hot fill to ${r.finalPressureBar.toStringAsFixed(0)} bar — '
              'settles to ${r.settledPressureBar!.toStringAsFixed(0)} bar '
              'at ${(r.settledTemperatureKelvin! - 273.15).toStringAsFixed(0)} °C.',
              style: AppTypography.caption,
            ),
          ),
        ],
        const Divider(height: Spacing.md),
        // Per-source litre breakdown.
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            if (r.cost.heliumLitres > 0)
              Text('He ${r.cost.heliumLitres.round()} L',
                  style: AppTypography.caption),
            if (r.cost.oxygenLitres > 0)
              Text('O₂ ${r.cost.oxygenLitres.round()} L',
                  style: AppTypography.caption),
            if (r.cost.topoffLitres > 0)
              Text('Top-off ${r.cost.topoffLitres.round()} L',
                  style: AppTypography.caption),
          ],
        ),
        const SizedBox(height: 4),
        if (r.cost.total > 0)
          Text(
            'Cost: ${r.cost.total.toStringAsFixed(2)} '
            '(He ${r.cost.heliumCost.toStringAsFixed(2)} · '
            'O₂ ${r.cost.oxygenCost.toStringAsFixed(2)} · '
            'air ${r.cost.airCost.toStringAsFixed(2)})',
            style: AppTypography.caption,
          ),
      ],
    );
  }

  String _verbForStep(BlendStep s) {
    switch (s.kind) {
      case BlendStepKind.drain:
        return 'DRAIN';
      case BlendStepKind.addHe:
        return 'ADD HE';
      case BlendStepKind.addO2:
        return 'ADD O₂';
      case BlendStepKind.addTopoff:
        return 'ADD MIX';
    }
  }

  Color _colorForStep(BlendStep s, ThemePalette palette) {
    switch (s.kind) {
      case BlendStepKind.drain:
        return SafetyColors.warning;
      case BlendStepKind.addHe:
        return palette.cell2;
      case BlendStepKind.addO2:
        return SafetyColors.success;
      case BlendStepKind.addTopoff:
        return palette.textSecondary;
    }
  }

  String _detailForStep(BlendStep s) {
    final bar = s.barAdded.abs().toStringAsFixed(0);
    if (s.kind == BlendStepKind.drain) {
      return '$bar bar to vent';
    }
    final src = s.source;
    // Pure helium is a blending source, not a breathing gas, so it keeps
    // its own label; everything else uses the shared naming scheme.
    final mixLabel = src.heliumPercent == 100
        ? 'He'
        : gasMixName(src.oxygenPercent, src.heliumPercent);
    return '$bar bar of $mixLabel';
  }
}

// ── Field primitives ─────────────────────────────────────────────────

class _IntField extends StatefulWidget {
  const _IntField({
    super.key,
    required this.label,
    required this.value,
    required this.suffix,
    required this.onChanged,
    required this.width,
  });
  final String label;
  final int value;
  final String suffix;
  final ValueChanged<int> onChanged;
  final double width;

  @override
  State<_IntField> createState() => _IntFieldState();
}

class _IntFieldState extends State<_IntField> {
  late final TextEditingController _ctrl;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '${widget.value}');
  }

  @override
  void didUpdateWidget(_IntField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _ctrl.text != '${widget.value}') {
      _ctrl.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        keyboardType: TextInputType.number,
        // Explicit raised fill so the input box pops against the
        // surface-card background of the surrounding _Card — without
        // this the global InputDecorationTheme's surface-card fill
        // makes the field invisible (looks like a label, not an
        // editable input).
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: context.palette.surfaceRaised,
          labelText: widget.label,
          suffixText: widget.suffix,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        ),
        onChanged: (s) {
          final v = int.tryParse(s);
          if (v != null) widget.onChanged(v);
        },
      ),
    );
  }
}

class _DoubleField extends StatefulWidget {
  const _DoubleField({
    super.key,
    required this.label,
    required this.value,
    required this.suffix,
    required this.onChanged,
    required this.width,
  });
  final String label;
  final double value;
  final String suffix;
  final ValueChanged<double> onChanged;
  final double width;

  @override
  State<_DoubleField> createState() => _DoubleFieldState();
}

class _DoubleFieldState extends State<_DoubleField> {
  late final TextEditingController _ctrl;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toStringAsFixed(0));
  }

  @override
  void didUpdateWidget(_DoubleField old) {
    super.didUpdateWidget(old);
    final next = widget.value.toStringAsFixed(0);
    if (!_focus.hasFocus && _ctrl.text != next) {
      _ctrl.text = next;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: context.palette.surfaceRaised,
          labelText: widget.label,
          suffixText: widget.suffix,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        ),
        onChanged: (s) {
          final v = double.tryParse(s);
          if (v != null) widget.onChanged(v);
        },
      ),
    );
  }
}

// ── Card wrapper ─────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({
    required this.accent,
    required this.label,
    required this.child,
  });
  final Color accent;
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.palette.surfaceCard,
        borderRadius: Radii.cardBr,
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.md, Spacing.sm, Spacing.md, Spacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.xs),
              child: Text(label, style: AppTypography.label),
            ),
            child,
          ],
        ),
      ),
    );
  }
}
