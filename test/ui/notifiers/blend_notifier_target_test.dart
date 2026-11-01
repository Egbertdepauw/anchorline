import 'package:ccrlogger/data/models/gas_analysis.dart';
import 'package:ccrlogger/ui/notifiers/blend_notifier.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late DateTime clock;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clock = DateTime.utc(2026, 10, 31, 12);
  });

  Future<BlendNotifier> newNotifier() async {
    final settings = SettingsNotifier();
    await settings.load();
    return BlendNotifier(settings: settings, now: () => clock);
  }

  group('recentTarget', () {
    test('is null on a fresh install, although the default target exists',
        () async {
      final n = await newNotifier();
      expect(n.targetOxygenPercent, 18);
      expect(n.targetHeliumPercent, 45);
      expect(n.recentTarget(), isNull);
    });

    test('returns the mix right after it was edited', () async {
      final n = await newNotifier();
      n.setTargetMix(21, 35);
      expect(n.recentTarget(), const DesiredMix(21, 35));
    });

    test('is still returned after 23 h 59 min and gone after 24 h 1 min',
        () async {
      final n = await newNotifier();
      n.setTargetMix(21, 35);

      clock = clock.add(const Duration(hours: 23, minutes: 59));
      expect(n.recentTarget(), const DesiredMix(21, 35));

      clock = clock.add(const Duration(minutes: 2));
      expect(n.recentTarget(), isNull);
    });

    test('a pressure edit also counts as an edit of the target', () async {
      final n = await newNotifier();
      n.setTargetPressure(200);
      // The mix is still the default one; the diver confirmed the target
      // by changing the fill pressure.
      expect(n.recentTarget(), const DesiredMix(18, 45));

      clock = clock.add(const Duration(hours: 24, minutes: 1));
      expect(n.recentTarget(), isNull);
    });

    test('a later edit restarts the 24 h window', () async {
      final n = await newNotifier();
      n.setTargetMix(21, 35);
      clock = clock.add(const Duration(hours: 20));
      n.setTargetPressure(200);
      clock = clock.add(const Duration(hours: 20));
      expect(n.recentTarget(), const DesiredMix(21, 35));
    });
  });

  group('persistence', () {
    test('a new notifier restores the mix, the pressure and the edit time',
        () async {
      final first = await newNotifier();
      first.setTargetMix(21, 35);
      first.setTargetPressure(200);
      await pumpEventQueue();

      clock = clock.add(const Duration(hours: 23));
      final second = await newNotifier();
      await second.loadTarget();

      expect(second.targetOxygenPercent, 21);
      expect(second.targetHeliumPercent, 35);
      expect(second.targetPressureBar, 200);
      // The edit time came back too: 23 h after the edit it is still
      // recent, 24 h 1 min after it, it is not.
      expect(second.recentTarget(), const DesiredMix(21, 35));
      clock = clock.add(const Duration(hours: 1, minutes: 1));
      expect(second.recentTarget(), isNull);
    });

    test('loadTarget does not touch the edit time', () async {
      final first = await newNotifier();
      first.setTargetMix(21, 35);
      await pumpEventQueue();

      clock = clock.add(const Duration(hours: 23));
      final second = await newNotifier();
      await second.loadTarget();

      // Had loadTarget stamped "now" (23 h after the edit), the target
      // would still be recent here.
      clock = clock.add(const Duration(hours: 1, minutes: 1));
      expect(second.recentTarget(), isNull);
    });

    test('with nothing stored it keeps the defaults and no recent target',
        () async {
      final n = await newNotifier();
      await n.loadTarget();
      expect(n.targetOxygenPercent, 18);
      expect(n.targetHeliumPercent, 45);
      expect(n.targetPressureBar, 230);
      expect(n.recentTarget(), isNull);
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
    late int storedAtMs;

    setUp(() {
      storedAtMs =
          clock.subtract(const Duration(hours: 30)).millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'blend_target_o2': 20,
        'blend_target_he': 30,
        'blend_target_pressure_bar': 210.0,
        'blend_target_edited_at': storedAtMs,
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
      // The edit time is the user's edit, not the stored 30 h old one.
      expect(n.recentTarget(), const DesiredMix(21, 35));

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
      expect(n.recentTarget(), const DesiredMix(20, 30));
    });

    test('applies the stored target when the user changed nothing', () async {
      final n = await newNotifier();
      await n.loadTarget();

      expect(n.targetOxygenPercent, 20);
      expect(n.targetHeliumPercent, 30);
      expect(n.targetPressureBar, 210);
      // Stored 30 h before "now": stale.
      expect(n.recentTarget(), isNull);
    });
  });
}
