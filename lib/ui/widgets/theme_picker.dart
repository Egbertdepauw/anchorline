import 'package:flutter/material.dart';

import '../notifiers/settings_notifier.dart';
import '../theme/app_themes.dart';
import '../theme/tokens.dart';

/// One row per available theme: name, a strip of four swatches from that
/// theme, and a check mark on the active one. Tapping a row applies it.
class ThemePicker extends StatelessWidget {
  const ThemePicker({super.key, required this.notifier});

  final SettingsNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: notifier,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final theme in AppThemes.all)
            ListTile(
              key: ValueKey('theme-${theme.id}'),
              title: Text(theme.name),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: Spacing.xs),
                child: _SwatchStrip(palette: theme.palette),
              ),
              trailing: theme.id == notifier.themeId
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => notifier.setThemeId(theme.id),
            ),
        ],
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
        for (final color in colors)
          Padding(
            padding: const EdgeInsets.only(right: Spacing.xs),
            child: Container(
              key: const ValueKey('theme-swatch'),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: color,
                borderRadius: Radii.chipBr,
                // Outline in the ambient theme so a swatch matching the
                // current background is still visible.
                border: Border.all(color: context.palette.surfaceBezel),
              ),
            ),
          ),
      ],
    );
  }
}
