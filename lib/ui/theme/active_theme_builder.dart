import 'package:flutter/material.dart';

import '../notifiers/settings_notifier.dart';
import 'app_themes.dart';

/// Rebuilds with the ThemeData of the theme selected in [settings].
///
/// Wrap MaterialApp in this and pass the result as its `theme`. Put the
/// app's home in [child] so it is not rebuilt each time a setting changes.
class ActiveThemeBuilder extends StatelessWidget {
  const ActiveThemeBuilder({
    super.key,
    required this.settings,
    required this.builder,
    this.child,
    this.enabled = kThemingEnabled,
  });

  final SettingsNotifier settings;

  /// When false the default theme is used whatever is stored; the stored
  /// value is left untouched.
  final bool enabled;
  final Widget Function(BuildContext context, ThemeData theme, Widget? child)
      builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      child: child,
      builder: (context, child) => builder(
        context,
        AppThemes.byId(enabled ? settings.themeId : null).themeData,
        child,
      ),
    );
  }
}
