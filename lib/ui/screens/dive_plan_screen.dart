/// Dive Plan tab — two-pane editor.
///
/// Tab 1 "Plan" reads as input → output: settings + gases + segments
/// stacked as accent-marked input cards, then the profile chart fused
/// to the stop-ladder output card. The diver edits at the top and
/// reads at the bottom — no scrolling around to correlate inputs to
/// results. Tab 2 "Bailout" follows the same pattern with the bailout
/// bottles editor and bailout section.
///
/// The plan-name field, save button, and saved-plans browser all live
/// in the app bar so they stay visible across both tabs. An amber pip
/// appears next to the name when the editor has unsaved changes. The
/// Save button shows "Overwrite" vs "Save" depending on whether the
/// loaded plan's name has been changed.
library;

import 'package:flutter/material.dart';

import '../../analysis/bailout/ascent_simulator.dart' show AscentStop;
import '../notifiers/dive_plan_notifier.dart';
import '../notifiers/settings_notifier.dart';
import '../theme/tokens.dart';
import '../widgets/bailout_section.dart';
import '../widgets/dive_profile_chart.dart';
import '../widgets/plan_bailout_bottles_editor.dart';
import '../widgets/plan_gases_editor.dart';
import '../widgets/plan_output_section.dart';
import '../widgets/plan_segments_editor.dart';
import '../widgets/plan_settings_panel.dart';
import '../widgets/saved_plans_sheet.dart';

class DivePlanScreen extends StatefulWidget {
  const DivePlanScreen({
    super.key,
    required this.notifier,
    required this.settings,
  });

  final DivePlanNotifier notifier;
  final SettingsNotifier settings;

  @override
  State<DivePlanScreen> createState() => _DivePlanScreenState();
}

class _DivePlanScreenState extends State<DivePlanScreen> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.notifier.planName ?? '',
    );
    widget.notifier.addListener(_syncNameFromNotifier);
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_syncNameFromNotifier);
    _nameController.dispose();
    super.dispose();
  }

  void _syncNameFromNotifier() {
    final notifierName = widget.notifier.planName ?? '';
    if (_nameController.text != notifierName) {
      _nameController.text = notifierName;
      _nameController.selection = TextSelection.collapsed(
        offset: _nameController.text.length,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: _PlanNameField(
            controller: _nameController,
            notifier: widget.notifier,
          ),
          actions: [
            _SaveButton(notifier: widget.notifier, onSave: _saveCurrent),
            IconButton(
              tooltip: 'Saved plans',
              icon: const Icon(Icons.folder_open),
              onPressed: _openSavedSheet,
            ),
            IconButton(
              key: const ValueKey('new-plan'),
              tooltip: 'New plan',
              icon: const Icon(Icons.note_add_outlined),
              onPressed: () => widget.notifier.newPlan(),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.show_chart), text: 'Plan'),
              Tab(icon: Icon(Icons.warning_amber_outlined), text: 'Bailout'),
            ],
          ),
        ),
        // Tap anywhere outside an input field to dismiss the keyboard.
        // iOS's numeric keyboard has no Return key, so without this the
        // user gets trapped behind the keyboard and can't reach the
        // tab bar / bottom nav. Per-scroll-view onDrag is set on each
        // tab's SingleChildScrollView as a secondary escape.
        //
        // ListenableBuilder is pushed *inside* each tab rather than
        // wrapping the TabBarView. Wrapping the whole TabBarView meant
        // every planner notification recreated the TabBarView widget,
        // which on macOS interrupted tab-bar hit-tests and produced an
        // intermittent "tap does nothing" feel when a recompute landed
        // on the same frame as the click. With per-tab builders the
        // TabBarView identity stays stable and only the tab content
        // rebuilds.
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: TabBarView(
            children: [
              ListenableBuilder(
                listenable: widget.notifier,
                builder: (context, _) => _PlanTab(
                  notifier: widget.notifier,
                  settings: widget.settings,
                  scheme: scheme,
                ),
              ),
              ListenableBuilder(
                listenable: widget.notifier,
                builder: (context, _) => _BailoutTab(
                  notifier: widget.notifier,
                  settings: widget.settings,
                  scheme: scheme,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveCurrent() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      final entered = await _promptForName();
      if (entered == null || entered.isEmpty) return;
      _nameController.text = entered;
      widget.notifier.setPlanName(entered);
    }
    final result = await widget.notifier.save();
    if (!mounted) return;
    final verb = result.wasOverwrite ? 'Overwrote' : 'Saved';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$verb "${result.name}"'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<String?> _promptForName() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Name this plan'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration:
              const InputDecoration(hintText: 'e.g. Zevenhuizerplas 31 m'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSavedSheet() async {
    final plans = await widget.notifier.dao.listSaved();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SavedPlansSheet(
        plans: plans,
        onLoad: (id) async {
          Navigator.of(context).pop();
          await widget.notifier.loadSaved(id);
        },
        onDelete: (id) async {
          await widget.notifier.dao.softDelete(id);
        },
      ),
    );
  }
}

/// Inline TextField that drives [DivePlanNotifier.setPlanName]. Renders
/// a small amber pip next to the name when the editor has unsaved
/// changes, so the diver knows their edits aren't yet on disk.
class _PlanNameField extends StatelessWidget {
  const _PlanNameField({required this.controller, required this.notifier});

  final TextEditingController controller;
  final DivePlanNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (notifier.isDirty)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _DirtyPip(color: AppColors.wreck.statusWarning),
          ),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: notifier.setPlanName,
            style: AppTypography.title.copyWith(
              color: AppColors.wreck.textPrimary,
            ),
            cursorColor: AppColors.wreck.accentPrimary,
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: InputBorder.none,
              hintText: 'Name this plan…',
              hintStyle: AppTypography.title.copyWith(
                color: AppColors.wreck.textMuted,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Small filled circle that signals "unsaved changes". Animates in/out
/// so an edit immediately surfaces a visual cue.
class _DirtyPip extends StatelessWidget {
  const _DirtyPip({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Unsaved changes',
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.6),
              blurRadius: 4,
              spreadRadius: 0,
            ),
          ],
        ),
      ),
    );
  }
}

/// App-bar save button that adapts:
///   - filled when there are unsaved changes (call-to-action)
///   - outlined when clean
///   - label changes between "Overwrite" (loaded plan, same name) and
///     "Save" (new plan or renamed) so the diver knows which side of
///     the smart-save fork they'll land on.
class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.notifier, required this.onSave});

  final DivePlanNotifier notifier;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final dirty = notifier.isDirty;
    final overwrite = notifier.nameMatchesSavedPlan;
    final label = overwrite ? 'Overwrite' : 'Save';
    final iconData =
        overwrite ? Icons.save_alt_outlined : Icons.save_outlined;
    final fg = AppColors.wreck.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: dirty
          ? FilledButton.tonalIcon(
              key: const ValueKey('save-as'),
              onPressed: onSave,
              icon: Icon(iconData, size: 18),
              label: Text(label),
              style: FilledButton.styleFrom(
                foregroundColor: fg,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            )
          : OutlinedButton.icon(
              key: const ValueKey('save-as'),
              onPressed: onSave,
              icon: Icon(iconData, size: 18),
              label: Text(label),
              style: OutlinedButton.styleFrom(
                foregroundColor: fg,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                side: BorderSide(color: AppColors.wreck.surfaceBezel),
              ),
            ),
    );
  }
}

// ── Tab 1: Plan ───────────────────────────────────────────────────────

class _PlanTab extends StatelessWidget {
  const _PlanTab({
    required this.notifier,
    required this.settings,
    required this.scheme,
  });

  final DivePlanNotifier notifier;
  final SettingsNotifier settings;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final result = notifier.result;
    final legs = <AscentStop>[
      if (result != null) ...result.profile,
      if (result != null) ...result.diveAscent,
    ];
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.md, Spacing.md, Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── INPUTS ────────────────────────────────────────────────
          _SectionCard(
            accent: AppColors.wreck.statusInfo,
            label: 'SETTINGS',
            // Settings panel renders its own header so suppress the
            // card-level title to avoid double-labelling.
            suppressLabel: true,
            child: PlanSettingsPanel(
              settings: settings,
              overrides: notifier.overrides,
              onChange: notifier.setOverrides,
              mode: notifier.mode,
              onModeChange: notifier.setMode,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          _SectionCard(
            accent: AppColors.wreck.cell2, // blue — input
            label: 'GASES',
            // Gases editor renders its own GASES header; suppress here.
            suppressLabel: true,
            child: PlanGasesEditor(
              gases: notifier.gases,
              segments: notifier.segments,
              onAdd: notifier.addGas,
              onRemove: notifier.removeGas,
              onReplace: notifier.replaceGas,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          _SectionCard(
            accent: AppColors.wreck.cell1, // green — segments are the
                                            // diver's actual dive shape
            label: 'SEGMENTS',
            suppressLabel: true,
            child: PlanSegmentsEditor(
              gases: notifier.gases,
              segments: notifier.segments,
              onAdd: notifier.addSegment,
              onRemove: notifier.removeSegment,
              onReplace: notifier.replaceSegment,
              onReorder: notifier.reorderSegments,
              mode: notifier.mode,
            ),
          ),
          const SizedBox(height: Spacing.md),
          // ── OUTPUTS ───────────────────────────────────────────────
          _SectionCard(
            accent: AppColors.wreck.accentPrimary, // amber — output
            label: 'OUTPUT',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (legs.isNotEmpty) ...[
                  DiveProfileChart(legs: legs),
                  const SizedBox(height: Spacing.sm),
                  const Divider(
                    height: 1,
                    color: Color(0xFF2A3A45),
                  ),
                  const SizedBox(height: Spacing.sm),
                ],
                PlanOutputSection(
                  result: result,
                  scheme: scheme,
                  mode: notifier.mode,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab 2: Bailout ─────────────────────────────────────────────────────

class _BailoutTab extends StatelessWidget {
  const _BailoutTab({
    required this.notifier,
    required this.settings,
    required this.scheme,
  });

  final DivePlanNotifier notifier;
  final SettingsNotifier settings;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final result = notifier.result;
    final triggerDepth = notifier.segments.isEmpty
        ? 0.0
        : notifier.segments
            .where((s) => s.durationMinutes > 0)
            .map((s) => s.depthMeters)
            .fold<double>(0, (acc, d) => d > acc ? d : acc);
    final bailoutLegs = <AscentStop>[
      if (result != null) ...result.profile,
      if (result?.bailout != null) ...result!.bailout.stops,
    ];
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.md, Spacing.md, Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionCard(
            accent: AppColors.wreck.statusWarning,
            label: 'BAILOUT BOTTLES',
            suppressLabel: true,
            child: PlanBailoutBottlesEditor(
              gases: notifier.gases,
              bottles: notifier.bailout,
              onAdd: notifier.addBailoutBottle,
              onRemove: notifier.removeBailoutBottle,
              onReplace: notifier.replaceBailoutBottle,
            ),
          ),
          const SizedBox(height: Spacing.md),
          _SectionCard(
            accent: AppColors.wreck.accentPrimary,
            label: 'BAILOUT PROFILE',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (bailoutLegs.isNotEmpty) ...[
                  DiveProfileChart(legs: bailoutLegs),
                  const SizedBox(height: Spacing.sm),
                  const Divider(height: 1, color: Color(0xFF2A3A45)),
                  const SizedBox(height: Spacing.sm),
                ],
                if (result != null)
                  BailoutSection(
                    result: result.bailout,
                    triggerDepthMeters: triggerDepth,
                    sacBottom: settings.bailoutSacBottom,
                    sacDeco: settings.bailoutSacDeco,
                    isGueConfig: settings.gueDiluentConfig,
                    bottomTimeBeforeTrigger: result.profile.fold(
                      Duration.zero,
                      (sum, leg) => sum + leg.duration,
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: Spacing.lg),
                    child: Text(
                      'Add gases and segments to see the bailout plan.',
                      style: AppTypography.caption,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Card-style container with a left accent bar — every input section
/// gets one, the output gets one. The accent colour groups the
/// sections semantically: blue/green for inputs (settings, gases,
/// segments), amber for the output, and a separate warning amber for
/// the bailout-bottles editor on Tab 2.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.accent,
    required this.label,
    required this.child,
    this.suppressLabel = false,
  });

  final Color accent;
  final String label;
  final Widget child;

  /// When the wrapped widget already renders its own section header
  /// (PlanSettingsPanel, the segment / gas editors) we skip the
  /// card-level label so the result doesn't read as "SETTINGS / SETTINGS".
  final bool suppressLabel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.wreck.surfaceCard,
        borderRadius: Radii.cardBr,
        border: Border(
          left: BorderSide(color: accent, width: 3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.md, Spacing.sm, Spacing.md, Spacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!suppressLabel)
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
