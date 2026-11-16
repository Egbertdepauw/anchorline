import 'package:ccrlogger/ui/notifiers/blend_notifier.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The device-local target memory: the Blend tab's inputs start from the last
// target. Which blends wait for an analysis is the open blends' business
// (#112), tested with its DAO, the Blend tab, the Analyse card and the log.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<BlendNotifier> newNotifier() async {
    final settings = SettingsNotifier();
    await settings.load();
    return BlendNotifier(settings: settings);
  }

  group('persistence', () {
    test('a new notifier restores the mix and the pressure', () async {
      final first = await newNotifier();
      first.setTargetMix(21, 35);
      first.setTargetPressure(200);
      await pumpEventQueue();

      final second = await newNotifier();
      await second.loadTarget();

      expect(second.targetOxygenPercent, 21);
      expect(second.targetHeliumPercent, 35);
      expect(second.targetPressureBar, 200);
    });

    test('with nothing stored it keeps the defaults', () async {
      final n = await newNotifier();
      await n.loadTarget();
      expect(n.targetOxygenPercent, 18);
      expect(n.targetHeliumPercent, 45);
      expect(n.targetPressureBar, 230);
    });

    test('loadTarget recomputes the blend and notifies', () async {
      final first = await newNotifier();
      first.setTargetMix(21, 35);
      await pumpEventQueue();

      final second = await newNotifier();
      var notified = 0;
      second.addListener(() => notified++);
      await second.loadTarget();

      expect(notified, 1);
      expect(second.result!.finalOxygenPercent, closeTo(21, 0.5));
      expect(second.result!.finalHeliumPercent, closeTo(35, 0.5));
    });

    test('loadTarget after dispose does not throw', () async {
      final n = await newNotifier();
      final loading = n.loadTarget();
      n.dispose();
      await loading;
    });
  });

  group('loadTarget finishing late', () {
    // The load is not awaited at startup, so it can finish after the
    // diver already typed into the Blend tab.
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'blend_target_o2': 20,
        'blend_target_he': 30,
        'blend_target_pressure_bar': 210.0,
      });
    });

    test('keeps a mix the user changed meanwhile', () async {
      final n = await newNotifier();
      final loading = n.loadTarget();
      n.setTargetMix(21, 35);
      await loading;

      expect(n.targetOxygenPercent, 21);
      expect(n.targetHeliumPercent, 35);
      // Untouched fields still come from storage.
      expect(n.targetPressureBar, 210);

      // And the user's mix is what ends up on the device.
      await pumpEventQueue();
      final reloaded = await newNotifier();
      await reloaded.loadTarget();
      expect(reloaded.targetOxygenPercent, 21);
      expect(reloaded.targetHeliumPercent, 35);
      expect(reloaded.targetPressureBar, 210);
    });

    test('keeps a pressure the user changed meanwhile', () async {
      final n = await newNotifier();
      final loading = n.loadTarget();
      n.setTargetPressure(200);
      await loading;

      expect(n.targetPressureBar, 200);
      expect(n.targetOxygenPercent, 20);
      expect(n.targetHeliumPercent, 30);
    });

    test('applies the stored target when the user changed nothing', () async {
      final n = await newNotifier();
      await n.loadTarget();

      expect(n.targetOxygenPercent, 20);
      expect(n.targetHeliumPercent, 30);
      expect(n.targetPressureBar, 210);
    });
  });
}
