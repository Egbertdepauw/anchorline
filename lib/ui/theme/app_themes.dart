import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'omarchy/catppuccin.dart';
import 'omarchy/ethereal.dart';
import 'omarchy/hackerman.dart';
import 'omarchy/miasma.dart';
import 'omarchy/omarchy_mapping.dart';
import 'omarchy/retro_82.dart';
import 'tokens.dart';

/// Whether the user can pick a theme, and whether a stored choice is
/// applied. Debug builds only until the remaining loose colour literals
/// are swept (stage 2): until then a non-default theme looks half-applied.
/// Stage 2 turns this on for everyone by changing this one constant.
const bool kThemingEnabled = kDebugMode;

/// One selectable theme.
class AppThemeDef {
  AppThemeDef({required this.id, required this.name, required this.palette});

  /// Stable identifier, persisted in the user's settings. Never rename one
  /// without a migration: an unknown id silently resolves to Wreck.
  final String id;

  /// Name shown in the picker.
  final String name;

  final ThemePalette palette;

  /// Built on first use and reused, so re-selecting a theme hands
  /// MaterialApp the identical ThemeData.
  late final ThemeData themeData = AppTheme.build(palette);
}

/// The themes the user can pick. To add one: add its OmarchyColors file
/// under omarchy/ and one entry here. The tests in app_themes_test.dart
/// then check it automatically.
class AppThemes {
  AppThemes._();

  static const String defaultId = 'wreck';

  static final List<AppThemeDef> all = List.unmodifiable([
    AppThemeDef(id: defaultId, name: 'Wreck', palette: AppColors.wreck),
    AppThemeDef(
      id: 'ethereal',
      name: 'Ethereal',
      palette: paletteFromOmarchy(etherealColors),
    ),
    AppThemeDef(
      id: 'retro82',
      name: 'Retro 82',
      palette: paletteFromOmarchy(retro82Colors),
    ),
    AppThemeDef(
      id: 'catppuccin',
      name: 'Catppuccin',
      palette: paletteFromOmarchy(catppuccinColors),
    ),
    AppThemeDef(
      id: 'hackerman',
      name: 'Hackerman',
      palette: paletteFromOmarchy(hackermanColors),
    ),
    AppThemeDef(
      id: 'miasma',
      name: 'Miasma',
      palette: paletteFromOmarchy(miasmaColors),
    ),
  ]);

  /// The theme with [id], or Wreck when [id] is null or not registered.
  static AppThemeDef byId(String? id) =>
      all.firstWhere((t) => t.id == id, orElse: () => all.first);
}
