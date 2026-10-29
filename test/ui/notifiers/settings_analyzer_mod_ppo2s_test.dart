import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults to 1.1 / 1.4 / 1.6', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsNotifier();
    await s.load();
    expect(s.analyzerModPpo2s, [1.1, 1.4, 1.6]);
  });

  test('persists, sorts, de-duplicates and survives a reload', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsNotifier();
    await s.load();
    var notified = 0;
    s.addListener(() => notified++);
    await s.setAnalyzerModPpo2s([1.6, 1.2, 1.2, 1.45]);
    expect(s.analyzerModPpo2s, [1.2, 1.45, 1.6]);
    expect(notified, 1);

    final reloaded = SettingsNotifier();
    await reloaded.load();
    expect(reloaded.analyzerModPpo2s, [1.2, 1.45, 1.6]);
  });

  test('drops out-of-range values and ignores an empty result', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsNotifier();
    await s.load();
    await s.setAnalyzerModPpo2s([0.1, 3.0, double.nan]);
    expect(s.analyzerModPpo2s, [1.1, 1.4, 1.6]);
    await s.setAnalyzerModPpo2s([1.3, 5]);
    expect(s.analyzerModPpo2s, [1.3]);
  });

  test('garbage in storage falls back to the default', () async {
    SharedPreferences.setMockInitialValues({
      'analyzer_mod_ppo2s': <String>['abc', '9'],
    });
    final s = SettingsNotifier();
    await s.load();
    expect(s.analyzerModPpo2s, [1.1, 1.4, 1.6]);
  });
}
