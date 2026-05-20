library;

import 'package:flutter/material.dart';

import '../notifiers/dive_plan_notifier.dart';
import '../notifiers/settings_notifier.dart';
import '../widgets/bailout_section.dart';
import '../widgets/plan_bailout_bottles_editor.dart';
import '../widgets/plan_gases_editor.dart';
import '../widgets/plan_output_section.dart';
import '../widgets/plan_segments_editor.dart';
import '../widgets/plan_settings_panel.dart';
import '../widgets/saved_plans_sheet.dart';
import '../theme/tokens.dart';

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
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan'),
        actions: [
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
      ),
      body: ListenableBuilder(
        listenable: widget.notifier,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Cave dive…')),
                  FilledButton.icon(
                    key: const ValueKey('save-as'),
                    onPressed: _promptSaveAs,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save as'),
                  ),
                ],
              ),
              const Divider(),
              PlanSettingsPanel(
                settings: widget.settings,
                overrides: widget.notifier.overrides,
                onChange: widget.notifier.setOverrides,
              ),
              const Divider(),
              PlanGasesEditor(
                gases: widget.notifier.gases,
                onAdd: widget.notifier.addGas,
                onRemove: widget.notifier.removeGas,
                onReplace: widget.notifier.replaceGas,
              ),
              const Divider(),
              PlanSegmentsEditor(
                gases: widget.notifier.gases,
                segments: widget.notifier.segments,
                onAdd: widget.notifier.addSegment,
                onRemove: widget.notifier.removeSegment,
                onReplace: widget.notifier.replaceSegment,
                onReorder: widget.notifier.reorderSegments,
                mode: widget.notifier.mode,
              ),
              const Divider(),
              PlanBailoutBottlesEditor(
                gases: widget.notifier.gases,
                bottles: widget.notifier.bailout,
                onAdd: widget.notifier.addBailoutBottle,
                onRemove: widget.notifier.removeBailoutBottle,
              ),
              const Divider(thickness: 2),
              PlanOutputSection(
                  result: widget.notifier.result, scheme: scheme),
              const SizedBox(height: Spacing.md),
              if (widget.notifier.result != null)
                BailoutSection(
                  result: widget.notifier.result!.bailout,
                  triggerDepthMeters: widget.notifier.segments.isEmpty
                      ? 0
                      : widget.notifier.segments
                          .where((s) => s.durationMinutes > 0)
                          .map((s) => s.depthMeters)
                          .fold<double>(
                              0, (acc, d) => d > acc ? d : acc),
                  sacBottom: widget.settings.bailoutSacBottom,
                  sacDeco: widget.settings.bailoutSacDeco,
                  isGueConfig: widget.settings.gueDiluentConfig,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _promptSaveAs() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Save plan as'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Plan name'),
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
    if (name != null && name.isNotEmpty) {
      await widget.notifier.saveAs(name);
    }
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
