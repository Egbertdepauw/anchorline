import 'package:flutter/material.dart';

/// One Omarchy theme's colours, copied unchanged from
/// `themes/<name>/colors.toml` in github.com/basecamp/omarchy. Field names
/// are the toml keys in camelCase. Do not adjust values here: the mapping
/// in omarchy_mapping.dart does any readability correction.
class OmarchyColors {
  const OmarchyColors({
    required this.accent,
    required this.selection,
    required this.muted,
    required this.background,
    required this.darkBackground,
    required this.darkerBackground,
    required this.lighterBackground,
    required this.foreground,
    required this.darkForeground,
    required this.lightForeground,
    required this.brightForeground,
    required this.red,
    required this.yellow,
    required this.orange,
    required this.green,
    required this.cyan,
    required this.blue,
    required this.magenta,
    required this.brown,
    required this.brightRed,
    required this.brightYellow,
    required this.brightGreen,
    required this.brightCyan,
    required this.brightBlue,
    required this.brightMagenta,
    required this.useOwnCellColors,
    required this.useOwnPpo2Color,
  });

  final Color accent;
  final Color selection;
  final Color muted;
  final Color background;
  final Color darkBackground;
  final Color darkerBackground;
  final Color lighterBackground;
  final Color foreground;
  final Color darkForeground;
  final Color lightForeground;
  final Color brightForeground;
  final Color red;
  final Color yellow;
  final Color orange;
  final Color green;
  final Color cyan;
  final Color blue;
  final Color magenta;
  final Color brown;
  final Color brightRed;
  final Color brightYellow;
  final Color brightGreen;
  final Color brightCyan;
  final Color brightBlue;
  final Color brightMagenta;

  /// Not from colors.toml. True when this theme's green/blue/magenta are
  /// distinct and readable enough to colour cells 1/2/3; false to keep the
  /// Wreck cell colours. A test checks this matches the rule.
  final bool useOwnCellColors;

  /// Not from colors.toml. True when this theme's yellow is distinct enough
  /// from its depth and setpoint traces to colour the PPO2 trace.
  final bool useOwnPpo2Color;
}
