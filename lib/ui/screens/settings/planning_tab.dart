import 'package:flutter/material.dart';

import '../../components/setting_row.dart';
import '../../components/value_stepper.dart';
import '../../notifiers/settings_notifier.dart';

/// Planning: the bailout planner's numbers. Steppers rather than sliders, so
/// a value is one tap off.
class PlanningTab extends StatelessWidget {
  const PlanningTab({super.key, required this.notifier});

  final SettingsNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: notifier,
      builder: (context, _) => ListView(
        children: [
          SettingsGroup(
            title: 'Bailout breathing rate (SAC)',
            children: [
              SettingRow(
                title: 'Bottom phase',
                helper: 'Until the first gas switch or half pressure',
                control: ValueStepper(
                  keyPrefix: 'settings-sac-bottom',
                  value: notifier.bailoutSacBottom,
                  min: 10,
                  max: 60,
                  unit: 'L/min',
                  onChanged: notifier.setBailoutSacBottom,
                ),
              ),
              SettingRow(
                title: 'Deco phase',
                helper: 'From the first deco stop to the surface',
                control: ValueStepper(
                  keyPrefix: 'settings-sac-deco',
                  value: notifier.bailoutSacDeco,
                  min: 10,
                  max: 60,
                  unit: 'L/min',
                  onChanged: notifier.setBailoutSacDeco,
                ),
              ),
            ],
          ),
          SettingsGroup(
            title: 'Ascent rate',
            children: [
              SettingRow(
                title: 'To the first stop',
                control: ValueStepper(
                  keyPrefix: 'settings-ascent-fast',
                  value: notifier.bailoutAscentRateFast,
                  min: 3,
                  max: 30,
                  unit: 'm/min',
                  onChanged: notifier.setBailoutAscentRateFast,
                ),
              ),
              SettingRow(
                title: 'Between stops',
                control: ValueStepper(
                  keyPrefix: 'settings-ascent-slow',
                  value: notifier.bailoutAscentRateSlow,
                  min: 3,
                  max: 30,
                  unit: 'm/min',
                  onChanged: notifier.setBailoutAscentRateSlow,
                ),
              ),
            ],
          ),
          SettingsGroup(
            title: 'Your bailout kit',
            children: [
              SettingRow(
                title: 'Diluent is bailout-capable',
                helper:
                    'On: bail out on the diluent. Off: 2–3 L diluent, plan a bottom-mix stage',
                onTap: () =>
                    notifier.setBailoutCapableDiluent(!notifier.bailoutCapableDiluent),
                control: Switch(
                  key: const ValueKey('settings-bailout-diluent'),
                  value: notifier.bailoutCapableDiluent,
                  onChanged: notifier.setBailoutCapableDiluent,
                ),
              ),
              SettingRow(
                title: '6.8 L / 300 bar stage',
                helper: 'Use it in bailout volumes',
                onTap: () => notifier
                    .setTank68L300Available(!notifier.tank68L300Available),
                control: Switch(
                  key: const ValueKey('settings-tank-68'),
                  value: notifier.tank68L300Available,
                  onChanged: notifier.setTank68L300Available,
                ),
              ),
              SettingRow(
                title: '12 L / 300 bar stage',
                helper: 'Use it in bailout volumes',
                onTap: () => notifier
                    .setTank12L300Available(!notifier.tank12L300Available),
                control: Switch(
                  key: const ValueKey('settings-tank-12'),
                  value: notifier.tank12L300Available,
                  onChanged: notifier.setTank12L300Available,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
