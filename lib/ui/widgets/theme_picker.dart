import 'package:flutter/material.dart';

import '../notifiers/settings_notifier.dart';
import '../theme/app_themes.dart';
import '../theme/tokens.dart';

/// A 3-column grid of tiles, one per available theme: name, a strip of four
/// swatches from that theme, and a check mark on the active one. Tapping a
/// tile applies it.
class ThemePicker extends StatelessWidget {
  const ThemePicker({super.key, required this.notifier});

  final SettingsNotifier notifier;

  static const _columns = 3;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: notifier,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg, vertical: Spacing.sm),
        // Tiles take a third of the width each and grow with their content,
        // so large text never overflows a fixed-ratio grid cell.
        child: LayoutBuilder(
          builder: (context, box) {
            final width =
                (box.maxWidth - Spacing.sm * (_columns - 1)) / _columns;
            return Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                for (final theme in AppThemes.all)
                  SizedBox(
                    width: width,
                    child: _ThemeTile(
                      theme: theme,
                      selected: theme.id == notifier.themeId,
                      onTap: () => notifier.setThemeId(theme.id),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final AppThemeDef theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      key: ValueKey('theme-${theme.id}'),
      onTap: onTap,
      borderRadius: Radii.chipBr,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm, vertical: Spacing.sm - 1),
        decoration: BoxDecoration(
          color: selected
              ? palette.accentPrimary.withValues(alpha: 0.12)
              : palette.surfaceCard,
          borderRadius: Radii.chipBr,
          border: Border.all(
            color: selected ? palette.accentPrimary : palette.surfaceBezel,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    theme.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body.copyWith(
                        fontSize: 12.5, color: palette.textPrimary),
                  ),
                ),
                if (selected)
                  Icon(Icons.check, size: 14, color: palette.accentPrimary),
              ],
            ),
            const SizedBox(height: Spacing.sm - 2),
            _SwatchStrip(palette: theme.palette),
          ],
        ),
      ),
    );
  }
}

class _SwatchStrip extends StatelessWidget {
  const _SwatchStrip({required this.palette});

  final ThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final colors = [
      palette.surfaceBg,
      palette.surfaceCard,
      palette.textPrimary,
      palette.accentPrimary,
    ];
    return Row(
      children: [
        for (var i = 0; i < colors.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : Spacing.xs - 1),
              child: Container(
                key: const ValueKey('theme-swatch'),
                height: 10,
                decoration: BoxDecoration(
                  color: colors[i],
                  borderRadius: BorderRadius.circular(1),
                  // Outline in the ambient theme so a swatch matching the
                  // current background is still visible.
                  border: Border.all(color: context.palette.surfaceBezel),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
