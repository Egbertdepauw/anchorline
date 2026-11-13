/// Gas Blend screen — partial-pressure blending planner.
///
/// The fill plan is a summary band at the top (one numbered stat per step,
/// litres per source and the cost) and updates as the inputs below it
/// change: Target, In the cylinder now, Top off with, then the folded-away
/// Fill options.
///
/// Settings → "Gas blending" carries the per-litre prices, default
/// top-off, default fill sequence, and ideal-gas vs real-gas toggle.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../analysis/blending/gas_blender.dart';
import '../../analysis/standard_mix_pick.dart';
import '../../data/db/open_blends_dao.dart';
import '../../data/models/gas_analysis.dart';
import '../components/hero_stat.dart';
import '../notifiers/blend_notifier.dart';
import '../notifiers/settings_notifier.dart';
import '../theme/data_colors.dart';
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';
import '../widgets/desired_mix_picker.dart';
import '../widgets/open_blends_section.dart';
import '../../analysis/gas_naming.dart';

class BlendScreen extends StatefulWidget {
  const BlendScreen({
    super.key,
    required this.notifier,
    required this.settings,
    this.openBlends,
    this.now = DateTime.now,
  });

  final BlendNotifier notifier;
  final SettingsNotifier settings;

  /// Where "Blend mix" saves to and the open list reads from. Null hides both.
  final OpenBlendsDaoLike? openBlends;
  final DateTime Function() now;

  @override
  State<BlendScreen> createState() => _BlendScreenState();
}

DesiredMix _standard(int o2, int he) =>
    kStandardMixes.firstWhere((m) => m == DesiredMix(o2, he));

class _BlendScreenState extends State<BlendScreen> {
  // Starts collapsed each time; not remembered.
  bool _optionsOpen = false;

  late final List<DesiredMix> _targetChips = [
    _standard(21, 35),
    _standard(18, 45),
    _standard(15, 55),
    _standard(32, 0),
    _standard(50, 0),
  ];
  late final List<DesiredMix> _topoffChips = [
    _standard(21, 0),
    _standard(32, 0),
    _standard(50, 0),
  ];

  Future<void> _pickRole(BuildContext chipContext) async {
    final box = chipContext.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(chipContext).context.findRenderObject()! as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final picked = await showMenu<GasRole>(
      context: chipContext,
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        topLeft.dy + box.size.height,
        overlay.size.width - topLeft.dx - box.size.width,
        0,
      ),
      items: [
        for (final r in kGasRoleButtonOrder)
          PopupMenuItem(value: r, child: Text(r.label)),
      ],
    );
    if (picked != null) widget.notifier.overrideRole(picked);
  }

  // True while the open blend is being written, so a second tap adds nothing.
  bool _saving = false;

  Future<void> _saveOpenBlend() async {
    final dao = widget.openBlends;
    if (dao == null || _saving) return;
    setState(() => _saving = true);
    final n = widget.notifier;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final draft = n.draftOpenBlend(
          blendedBy: widget.settings.yourInitials, now: widget.now());
      await dao.add(draft);
      n.openBlendSaved();
      messenger.showSnackBar(SnackBar(
        content: Text('${draft.target.name} added to open blends'),
      ));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Could not save the open blend: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTopoffOther() async {
    final picked = await showOtherMixDialog(context);
    if (picked != null) {
      widget.notifier.setTopoff(picked.o2Percent, picked.hePercent);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tap anywhere outside an input field to dismiss the keyboard.
    // iOS's numeric keyboard has no Return key, so without this the
    // user can't get the keyboard out of the way to reach the bottom
    // nav. `translucent` makes hit-testing still pass through to
    // children (chips / dropdowns / switch).
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListenableBuilder(
        listenable: widget.notifier,
        builder: (context, _) {
          final n = widget.notifier;
          final target = DesiredMix(n.targetOxygenPercent, n.targetHeliumPercent);
          final topoff = DesiredMix(n.topoffOxygenPercent, n.topoffHeliumPercent);
          return SingleChildScrollView(
            // Dragging the content also dismisses — second escape hatch
            // for users who don't think to tap outside.
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(bottom: Spacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PlanBand(
                  target: target,
                  targetPressureBar: n.targetPressureBar,
                  topoff: topoff,
                  result: n.result,
                ),
                _RoleRow(
                  roleLabel: n.role.label,
                  reason: n.roleOverridden ? null : n.roleGuess.reason,
                  onTap: _pickRole,
                  canSave: widget.openBlends != null,
                  onSave: _saving ? null : _saveOpenBlend,
                ),
                _Section(
                  label: 'Target',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ChipGrid(children: [
                        for (final m in _targetChips)
                          _MixChip(
                            key: ValueKey(
                                'blend-target-chip-${m.o2Percent}-${m.hePercent}'),
                            label: m.name,
                            selected: m == target,
                            onTap: () {
                              // Release a focused field so it refreshes.
                              FocusScope.of(context).unfocus();
                              n.setTargetMix(m.o2Percent, m.hePercent);
                            },
                          ),
                      ]),
                      const SizedBox(height: Spacing.sm),
                      _FieldGrid(columns: 3, children: [
                        _IntField(
                          key: const ValueKey('tgt-o2'),
                          label: 'O₂',
                          value: n.targetOxygenPercent,
                          suffix: '%',
                          onChanged: (v) =>
                              n.setTargetMix(v, n.targetHeliumPercent),
                        ),
                        _IntField(
                          key: const ValueKey('tgt-he'),
                          label: 'He',
                          value: n.targetHeliumPercent,
                          suffix: '%',
                          onChanged: (v) =>
                              n.setTargetMix(n.targetOxygenPercent, v),
                        ),
                        _DoubleField(
                          key: const ValueKey('tgt-pressure'),
                          label: 'Pressure',
                          value: n.targetPressureBar,
                          suffix: 'bar',
                          onChanged: n.setTargetPressure,
                        ),
                      ]),
                    ],
                  ),
                ),
                _Section(
                  label: 'In the cylinder now',
                  child: _FieldGrid(columns: 4, children: [
                    _IntField(
                      key: const ValueKey('cur-o2'),
                      label: 'O₂',
                      value: n.currentOxygenPercent,
                      suffix: '%',
                      onChanged: (v) =>
                          n.setCurrentMix(v, n.currentHeliumPercent),
                    ),
                    _IntField(
                      key: const ValueKey('cur-he'),
                      label: 'He',
                      value: n.currentHeliumPercent,
                      suffix: '%',
                      onChanged: (v) =>
                          n.setCurrentMix(n.currentOxygenPercent, v),
                    ),
                    _DoubleField(
                      key: const ValueKey('cur-pressure'),
                      label: 'Pressure',
                      value: n.currentPressureBar,
                      suffix: 'bar',
                      onChanged: n.setCurrentPressure,
                    ),
                    _DoubleField(
                      key: const ValueKey('cur-capacity'),
                      label: 'Size',
                      value: n.waterCapacityL,
                      suffix: 'L',
                      onChanged: n.setWaterCapacity,
                    ),
                  ]),
                ),
                _Section(
                  label: 'Top off with',
                  child: _ChipGrid(children: [
                    for (final m in [
                      ..._topoffChips,
                      if (!_topoffChips.contains(topoff)) topoff,
                    ])
                      _MixChip(
                        key: ValueKey(
                            'blend-topoff-chip-${m.o2Percent}-${m.hePercent}'),
                        label: m.name,
                        selected: m == topoff,
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          n.setTopoff(m.o2Percent, m.hePercent);
                        },
                      ),
                    _MixChip(
                      key: const ValueKey('blend-topoff-other'),
                      label: 'Other…',
                      selected: false,
                      onTap: _pickTopoffOther,
                    ),
                  ]),
                ),
                _FillOptions(
                  open: _optionsOpen,
                  onToggle: () =>
                      setState(() => _optionsOpen = !_optionsOpen),
                  sequence: n.sequence,
                  useRealGas: n.useRealGas,
                  fillTempC: n.fillTempC,
                  settledTempC: n.settledTempC,
                  onSequenceChange: n.setSequence,
                  onUseRealGasChange: n.setUseRealGas,
                  onFillTempChange: n.setFillTempC,
                  onSettledTempChange: n.setSettledTempC,
                ),
                if (widget.openBlends != null)
                  OpenBlendsSection(
                    dao: widget.openBlends!,
                    settings: widget.settings,
                    now: widget.now,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The role control (tap to change it) and the "Blend mix" button, under the plan
/// band.
class _RoleRow extends StatelessWidget {
  const _RoleRow({
    required this.roleLabel,
    required this.reason,
    required this.onTap,
    required this.canSave,
    required this.onSave,
  });
  final String roleLabel;
  final String? reason;
  final void Function(BuildContext chipContext) onTap;
  final bool canSave;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = reason == null ? roleLabel : '$roleLabel ($reason)';
    return Container(
      padding: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.sm + 4, Spacing.md, Spacing.sm + 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.surfaceRaised)),
      ),
      child: Row(
        children: [
          // The role is a guess the diver can change: a dropdown-style
          // control (label, value, chevron), not a plain chip.
          Flexible(
            child: Builder(
              builder: (chipContext) => Tooltip(
                message: 'Tap to change the cylinder role',
                child: InkWell(
                  key: const ValueKey('blend-role-chip'),
                  onTap: () => onTap(chipContext),
                  borderRadius: Radii.chipBr,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 40),
                    padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                    decoration: BoxDecoration(
                      borderRadius: Radii.chipBr,
                      color: palette.surfaceRaised,
                      border: Border.all(color: palette.textMuted),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Role ',
                            style: AppTypography.body.copyWith(
                                fontSize: 13, color: palette.textMuted)),
                        Flexible(
                          child: Text(text,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.body.copyWith(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: palette.textPrimary)),
                        ),
                        Icon(Icons.arrow_drop_down,
                            size: 22, color: palette.textPrimary),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (canSave) ...[
            const SizedBox(width: Spacing.sm),
            FilledButton.icon(
              key: const ValueKey('blend-save-open'),
              onPressed: onSave,
              icon: const Icon(Icons.playlist_add_check),
              label: const Text('Blend mix'),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Layout primitives ────────────────────────────────────────────────

/// An input group: a micro-label over its content, with a hairline under it.
class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.sm + 4, Spacing.md, Spacing.sm + 4),
      decoration: BoxDecoration(
        border:
            Border(bottom: BorderSide(color: palette.surfaceRaised)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: Text(label,
                style: AppTypography.label
                    .copyWith(color: palette.accentPrimary)),
          ),
          child,
        ],
      ),
    );
  }
}

/// Fields side by side in [columns] equal columns; on a narrow phone or at
/// large text they drop to two columns and wrap instead of overflowing.
class _FieldGrid extends StatelessWidget {
  const _FieldGrid({required this.columns, required this.children});
  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth < 340 || scale > 1.15 ? 2 : columns;
      const gap = Spacing.sm;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final f in children) SizedBox(width: w, child: f)],
      );
    });
  }
}

/// Gas chips in equal columns, as many as fit at [_minChipWidth] each and
/// never fewer than two: three on an iPhone 15, where they line up with the
/// three fields under the target chips, and more on wider screens. Large
/// text raises the minimum, so a phone drops to two columns first.
class _ChipGrid extends StatelessWidget {
  const _ChipGrid({required this.children});
  final List<Widget> children;

  static const double _minChipWidth = 100;

  @override
  Widget build(BuildContext context) {
    final scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
    return LayoutBuilder(builder: (context, c) {
      const gap = Spacing.sm;
      final cols = math.max(
          2, ((c.maxWidth + gap) / (_minChipWidth * scale + gap)).floor());
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final f in children) SizedBox(width: w, child: f)],
      );
    });
  }
}

class _MixChip extends StatelessWidget {
  const _MixChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.chipBr,
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: Radii.chipBr,
            color: selected
                ? palette.accentPrimary.withValues(alpha: 0.18)
                : palette.surfaceRaised,
            border: Border.all(
              color: selected ? palette.accentPrimary : palette.surfaceBezel,
            ),
          ),
          child: Text(label,
              style: AppTypography.body.copyWith(
                  fontSize: 13, color: palette.textPrimary)),
        ),
      ),
    );
  }
}

// ── Fill options (folded away) ───────────────────────────────────────

class _FillOptions extends StatelessWidget {
  const _FillOptions({
    required this.open,
    required this.onToggle,
    required this.sequence,
    required this.useRealGas,
    required this.fillTempC,
    required this.settledTempC,
    required this.onSequenceChange,
    required this.onUseRealGasChange,
    required this.onFillTempChange,
    required this.onSettledTempChange,
  });

  final bool open;
  final VoidCallback onToggle;
  final FillSequence sequence;
  final bool useRealGas;
  final double fillTempC;
  final double settledTempC;
  final ValueChanged<FillSequence> onSequenceChange;
  final ValueChanged<bool> onUseRealGasChange;
  final ValueChanged<double> onFillTempChange;
  final ValueChanged<double> onSettledTempChange;

  static String sequenceLabel(FillSequence s) {
    switch (s) {
      case FillSequence.heThenO2ThenTopoff:
        return 'He → O₂ → top-off';
      case FillSequence.o2ThenHeThenTopoff:
        return 'O₂ → He → top-off';
      case FillSequence.o2ThenTopoffThenHe:
        return 'O₂ → top-off → He';
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final summary = '${sequenceLabel(sequence)} · '
        '${useRealGas ? 'real gas' : 'ideal gas'} · '
        '${fillTempC.toStringAsFixed(0)} °C';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const ValueKey('blend-fill-options'),
          onTap: onToggle,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: Row(
                children: [
                  Icon(open ? Icons.expand_more : Icons.chevron_right,
                      size: 18, color: palette.textSecondary),
                  const SizedBox(width: Spacing.sm),
                  Text('Fill options',
                      style: AppTypography.body
                          .copyWith(color: palette.textSecondary)),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(summary,
                        textAlign: TextAlign.end,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption
                            .copyWith(color: palette.textMuted)),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, 0, Spacing.md, Spacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Fill order', style: AppTypography.caption),
                DropdownButton<FillSequence>(
                  key: const ValueKey('blend-fill-order'),
                  value: sequence,
                  isDense: true,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final s in FillSequence.values)
                      DropdownMenuItem(
                        value: s,
                        child: Text(sequenceLabel(s),
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) onSequenceChange(v);
                  },
                ),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Real-gas maths (Z)',
                          style: AppTypography.caption),
                    ),
                    Switch.adaptive(
                      key: const ValueKey('use-real-gas'),
                      value: useRealGas,
                      onChanged: onUseRealGasChange,
                    ),
                  ],
                ),
                _FieldGrid(columns: 2, children: [
                  _DoubleField(
                    key: const ValueKey('fill-temp'),
                    label: 'Fill temp',
                    value: fillTempC,
                    suffix: '°C',
                    onChanged: onFillTempChange,
                  ),
                  _DoubleField(
                    key: const ValueKey('settled-temp'),
                    label: 'Settled temp',
                    value: settledTempC,
                    suffix: '°C',
                    onChanged: onSettledTempChange,
                  ),
                ]),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Plan band ────────────────────────────────────────────────────────

class _PlanBand extends StatelessWidget {
  const _PlanBand({
    required this.target,
    required this.targetPressureBar,
    required this.topoff,
    required this.result,
  });
  final DesiredMix target;
  final double targetPressureBar;
  final DesiredMix topoff;
  final BlendResult? result;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      key: const ValueKey('blend-plan-band'),
      color: palette.surfaceRaised,
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 10,
            children: [
              Text(target.name,
                  style: AppTypography.headline.copyWith(
                      fontSize: 26, color: palette.textPrimary)),
              Text('to ${targetPressureBar.toStringAsFixed(0)} bar',
                  style: AppTypography.body
                      .copyWith(color: palette.textSecondary)),
            ],
          ),
          const SizedBox(height: 12),
          ..._plan(context),
        ],
      ),
    );
  }

  List<Widget> _plan(BuildContext context) {
    final palette = context.palette;
    final r = result;
    if (r == null || r.steps.isEmpty && r.isOk) {
      return [
        Text(
          'Nothing to do — current contents already match the target.',
          style: AppTypography.caption.copyWith(color: palette.textSecondary),
        ),
      ];
    }
    if (!r.isOk) {
      return [
        _Banner(
          color: SafetyColors.danger,
          text: r.errorMessage ?? 'Impossible blend.',
        ),
      ];
    }
    return [
      HeroStatRow(children: [
        for (var i = 0; i < r.steps.length; i++) _stepStat(context, i, r.steps[i]),
      ]),
      if (r.drainToPressureBar != null) ...[
        const SizedBox(height: Spacing.sm),
        _Banner(
          color: SafetyColors.warning,
          text: 'Drain to ${r.drainToPressureBar!.toStringAsFixed(0)} bar '
              'first — current contents have more of one gas than the '
              'target needs.',
        ),
      ],
      // Hot-fill compensation banner: shown when fill temp ≠ settled
      // so the diver knows the gauge will drop after cooldown.
      if (r.settledPressureBar != null &&
          r.settledTemperatureKelvin != null) ...[
        const SizedBox(height: Spacing.sm),
        _Banner(
          color: SafetyColors.info,
          text: 'Hot fill to ${r.finalPressureBar.toStringAsFixed(0)} bar — '
              'settles to ${r.settledPressureBar!.toStringAsFixed(0)} bar '
              'at ${(r.settledTemperatureKelvin! - 273.15).toStringAsFixed(0)} °C.',
        ),
      ],
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.only(top: 9),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: palette.surfaceBezel)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                _litres(r),
                style: AppTypography.readoutSm.copyWith(
                    fontSize: 12, color: palette.textSecondary),
              ),
            ),
            if (r.cost.total > 0)
              InkWell(
                key: const ValueKey('blend-cost'),
                onTap: () => _showCost(context, r.cost),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                      minHeight: 44, minWidth: 44),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(left: Spacing.sm),
                      child: Text(r.cost.total.toStringAsFixed(2),
                          style: AppTypography.readoutSm.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: palette.textPrimary)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  String _litres(BlendResult r) => [
        if (r.cost.heliumLitres > 0) 'He ${r.cost.heliumLitres.round()} L',
        if (r.cost.oxygenLitres > 0) 'O₂ ${r.cost.oxygenLitres.round()} L',
        if (r.cost.topoffLitres > 0)
          '${gasMixName(topoff.o2Percent, topoff.hePercent)} '
              '${r.cost.topoffLitres.round()} L',
      ].join(' · ');

  Widget _stepStat(BuildContext context, int i, BlendStep s) {
    final palette = context.palette;
    final bar = s.barAdded.abs().toStringAsFixed(0);
    final String label;
    final Color color;
    switch (s.kind) {
      case BlendStepKind.drain:
        label = 'Drain';
        color = SafetyColors.warning;
      case BlendStepKind.addHe:
        label = 'Helium';
        color = DataColors.helium;
      case BlendStepKind.addO2:
        label = 'Oxygen';
        color = SafetyColors.success;
      case BlendStepKind.addTopoff:
        // Pure helium stays "Helium"; everything else is named by mix.
        label = s.source.heliumPercent == 100
            ? 'Helium'
            : gasMixName(s.source.oxygenPercent, s.source.heliumPercent);
        color = palette.textPrimary;
    }
    final sign = s.kind == BlendStepKind.drain ? '−' : '+';
    return Column(
      key: ValueKey('blend-step-$i'),
      children: [
        HeroStat(
          value: '$sign$bar',
          unit: 'bar',
          label: '${i + 1} · $label',
          valueColor: color,
          valueSize: 24,
          centered: true,
          tight: true,
        ),
        const SizedBox(height: 3),
        Text('to ${s.cumulativePressureBar.toStringAsFixed(0)}',
            style: AppTypography.readoutSm.copyWith(
                fontSize: 11, color: palette.textMuted)),
      ],
    );
  }

  void _showCost(BuildContext context, BlendCost c) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cost'),
        content: Text(
          '${c.total.toStringAsFixed(2)} '
          '(He ${c.heliumCost.toStringAsFixed(2)} · '
          'O₂ ${c.oxygenCost.toStringAsFixed(2)} · '
          'air ${c.airCost.toStringAsFixed(2)})',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.text});
  final Color color;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: Radii.cardBr,
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Text(text, style: AppTypography.caption),
    );
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
  });
  final String label;
  final int value;
  final String suffix;
  final ValueChanged<int> onChanged;

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
    return TextField(
      controller: _ctrl,
      focusNode: _focus,
      keyboardType: TextInputType.number,
      // Explicit raised fill so the input box pops against the
      // surface background of the section — without
      // this the global InputDecorationTheme's card fill
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
  });
  final String label;
  final double value;
  final String suffix;
  final ValueChanged<double> onChanged;

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
    return TextField(
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
    );
  }
}

