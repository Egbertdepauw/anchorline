import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to true when no value is persisted', () async {
    SharedPreferences.setMockInitialValues({});
    final n = SettingsNotifier();
    await n.load();
    expect(n.useSpeedColoredGraph, isTrue);
  });

  test('reads persisted false on load', () async {
    SharedPreferences.setMockInitialValues({'use_speed_colored_graph': false});
    final n = SettingsNotifier();
    await n.load();
    expect(n.useSpeedColoredGraph, isFalse);
  });

  test('toggle persists across reload', () async {
    SharedPreferences.setMockInitialValues({});
    final n1 = SettingsNotifier();
    await n1.load();
    expect(n1.useSpeedColoredGraph, isTrue);
    await n1.setUseSpeedColoredGraph(false);
    expect(n1.useSpeedColoredGraph, isFalse);

    final n2 = SettingsNotifier();
    await n2.load();
    expect(n2.useSpeedColoredGraph, isFalse);
  });

  test('notifies listeners on toggle', () async {
    SharedPreferences.setMockInitialValues({});
    final n = SettingsNotifier();
    await n.load();
    var calls = 0;
    n.addListener(() => calls++);
    await n.setUseSpeedColoredGraph(false);
    expect(calls, 1);
    // Setting the same value is a no-op.
    await n.setUseSpeedColoredGraph(false);
    expect(calls, 1);
  });
}
