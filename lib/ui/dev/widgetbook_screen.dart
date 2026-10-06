import 'package:flutter/material.dart';

import '../components/accent_button.dart';
import '../components/app_card.dart';
import '../components/bezel_panel.dart';
import '../components/data_row.dart' as components;
import '../components/ghost_button.dart';
import '../components/icon_chip.dart';
import '../components/numeric_readout.dart';
import '../components/section_header.dart';
import '../components/stat_tile.dart';
import '../components/status_dot.dart';
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';

class WidgetbookScreen extends StatelessWidget {
  const WidgetbookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Widgetbook')),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
          const SectionHeader('Palette'),
          _swatchRow(context, 'surface.bg', AppColors.wreck.surfaceBg),
          _swatchRow(context, 'surface.card', AppColors.wreck.surfaceCard),
          _swatchRow(context, 'surface.raised', AppColors.wreck.surfaceRaised),
          _swatchRow(context, 'accent.primary', AppColors.wreck.accentPrimary),
          _swatchRow(context, 'status.success', SafetyColors.success),
          _swatchRow(context, 'status.warning', SafetyColors.warning),
          _swatchRow(context, 'status.danger', SafetyColors.danger),
          _swatchRow(context, 'cell.1', AppColors.wreck.cell1),
          _swatchRow(context, 'cell.2', AppColors.wreck.cell2),
          _swatchRow(context, 'cell.3', AppColors.wreck.cell3),
          const SizedBox(height: Spacing.xl),
          const SectionHeader('Cards'),
          const AppCard(child: Text('AppCard (no bezel)')),
          const SizedBox(height: Spacing.sm),
          const AppCard(
            withBezel: true,
            child: Text('AppCard withBezel: true'),
          ),
          const SizedBox(height: Spacing.sm),
          const BezelPanel(child: Text('BezelPanel — outline only')),
          const SizedBox(height: Spacing.xl),
          const SectionHeader('Numeric readouts'),
          const Wrap(
            spacing: Spacing.lg,
            runSpacing: Spacing.md,
            children: [
              NumericReadout('57:30', size: ReadoutSize.lg),
              NumericReadout('18.0 m', size: ReadoutSize.md),
              NumericReadout('1.30 bar', size: ReadoutSize.sm),
            ],
          ),
          const SizedBox(height: Spacing.xl),
          const SectionHeader('Stat tiles'),
          const Wrap(
            spacing: Spacing.lg,
            runSpacing: Spacing.md,
            children: [
              StatTile(label: 'Max depth', unit: 'm', value: '18.0'),
              StatTile(
                  label: 'Duration', unit: 'min', value: '57:30'),
              StatTile(
                  label: 'PPO2 (bar)',
                  value: '1.30',
                  hint: '0.70 / 1.30'),
              StatTile(label: 'CNS', value: '45%'),
            ],
          ),
          const SizedBox(height: Spacing.xl),
          const SectionHeader('Data rows'),
          const components.DataRow(
              label: 'Water type', value: 'Fresh — 1.000 g/L'),
          const components.DataRow(
              label: 'Atm. pressure', value: '1003 mbar'),
          const components.DataRow(
              label: 'Surface GF', value: '14%', numeric: true),
          const SizedBox(height: Spacing.xl),
          const SectionHeader('Buttons'),
          Row(
            children: [
              AccentButton(
                  icon: Icons.cloud_upload_outlined,
                  label: 'Push to Subsurface',
                  onPressed: () {}),
              const SizedBox(width: Spacing.sm),
              GhostButton(label: 'Cancel', onPressed: () {}),
              const SizedBox(width: Spacing.sm),
              const AccentButton(label: 'Disabled', onPressed: null),
            ],
          ),
          const SizedBox(height: Spacing.xl),
          const SectionHeader('Chips + status'),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              IconChip(label: 'CCR', icon: Icons.air, onTap: () {}),
              IconChip(label: 'Deep', icon: Icons.south, onTap: () {}),
              const IconChip(label: 'WIP'),
              Row(mainAxisSize: MainAxisSize.min, children: [
                StatusDot(color: SafetyColors.success),
                const SizedBox(width: Spacing.xs),
                const Text('online'),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                StatusDot(color: SafetyColors.warning),
                const SizedBox(width: Spacing.xs),
                const Text('skipped'),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                StatusDot(color: SafetyColors.danger),
                const SizedBox(width: Spacing.xs),
                const Text('failed'),
              ]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _swatchRow(BuildContext context, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: Radii.cardBr,
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          const SizedBox(width: Spacing.md),
          SizedBox(width: 140, child: Text(label)),
          NumericReadout(
            // ignore: deprecated_member_use
            '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
            size: ReadoutSize.sm,
          ),
        ],
      ),
    );
  }
}
