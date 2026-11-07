import 'package:flutter/material.dart';

import '../../components/setting_row.dart';
import '../../components/value_stepper.dart';
import '../../notifiers/settings_notifier.dart';
import '../../widgets/theme_picker.dart';
import 'settings_fields.dart';

/// General: the look of the app, your initials, and how dive profiles are
/// drawn.
class GeneralTab extends StatelessWidget {
  const GeneralTab({
    super.key,
    required this.notifier,
    required this.showThemePicker,
  });

  final SettingsNotifier notifier;
  final bool showThemePicker;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: notifier,
      builder: (context, _) => ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          if (showThemePicker)
            SettingsGroup(
              title: 'Theme',
              children: [ThemePicker(notifier: notifier)],
            ),
          SettingsGroup(
            title: 'You',
            children: [
              SettingRow(
                title: 'Your initials',
                helper: 'Fills "Analysed by" and goes on cylinder labels',
                control: SettingTextField(
                  key: const ValueKey('settings-your-initials'),
                  initialValue: notifier.yourInitials ?? '',
                  width: 96,
                  onChanged: notifier.setYourInitials,
                ),
              ),
            ],
          ),
          SettingsGroup(
            title: 'Dive profile',
            children: [
              SettingRow(
                title: 'Colour by ascent speed',
                helper: 'Depth trace turns red above 9 m/min',
                onTap: () => notifier
                    .setUseSpeedColoredGraph(!notifier.useSpeedColoredGraph),
                control: Switch(
                  key: const ValueKey('settings-speed-graph'),
                  value: notifier.useSpeedColoredGraph,
                  onChanged: notifier.setUseSpeedColoredGraph,
                ),
              ),
              SettingRow(
                title: 'Watermark',
                helper: 'Behind the profile; 0 hides it',
                control: ValueStepper(
                  keyPrefix: 'settings-watermark',
                  value: (notifier.watermarkOpacity * 100).round(),
                  min: 0,
                  max: 20,
                  unit: '%',
                  onChanged: (v) => notifier.setWatermarkOpacity(v / 100),
                ),
              ),
              SettingRow(
                title: 'Count O₂ as narcotic in END',
                helper: 'Off: only N₂ counts',
                onTap: () =>
                    notifier.setEndCountsOxygen(!notifier.endCountsOxygen),
                control: Switch(
                  key: const ValueKey('settings-end-counts-o2'),
                  value: notifier.endCountsOxygen,
                  onChanged: notifier.setEndCountsOxygen,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
