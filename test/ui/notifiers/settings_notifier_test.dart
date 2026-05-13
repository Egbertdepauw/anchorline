import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/widgets/map_tile_sources.dart' show MapLayerStyle;
import 'package:ccrlogger/ui/widgets/trace_segmented_bar.dart' show TraceType;
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

  group('visibleTraces', () {
    test('defaults to {ppo2, setpoint, deco, gasChanges} when prefs empty',
        () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      expect(n.visibleTraces, {
        TraceType.ppo2,
        TraceType.setpoint,
        TraceType.deco,
        TraceType.gasChanges,
      });
    });

    test('toggleTrace flips membership and notifies', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      var notifyCount = 0;
      n.addListener(() => notifyCount++);
      await n.toggleTrace(TraceType.cells);
      expect(n.visibleTraces.contains(TraceType.cells), isTrue);
      expect(notifyCount, 1);
      await n.toggleTrace(TraceType.cells);
      expect(n.visibleTraces.contains(TraceType.cells), isFalse);
      expect(notifyCount, 2);
    });

    test('toggleTrace persists across reload', () async {
      SharedPreferences.setMockInitialValues({});
      final n1 = SettingsNotifier();
      await n1.load();
      await n1.toggleTrace(TraceType.cells); // add
      await n1.toggleTrace(TraceType.setpoint); // remove (was in defaults)
      final n2 = SettingsNotifier();
      await n2.load();
      expect(n2.visibleTraces.contains(TraceType.cells), isTrue);
      expect(n2.visibleTraces.contains(TraceType.setpoint), isFalse);
    });
  });

  group('mapLayerStyle', () {
    test('defaults to MapLayerStyle.normal when prefs empty', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      expect(n.mapLayerStyle, MapLayerStyle.normal);
    });

    test('setMapLayerStyle persists across reload', () async {
      SharedPreferences.setMockInitialValues({});
      final n1 = SettingsNotifier();
      await n1.load();
      await n1.setMapLayerStyle(MapLayerStyle.satellite);
      final n2 = SettingsNotifier();
      await n2.load();
      expect(n2.mapLayerStyle, MapLayerStyle.satellite);
    });

    test('setMapLayerStyle no-ops when style unchanged', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      var notifyCount = 0;
      n.addListener(() => notifyCount++);
      await n.setMapLayerStyle(MapLayerStyle.normal); // already normal
      expect(notifyCount, 0);
    });
  });

  group('watermarkOpacity', () {
    test('defaults to 0.06 when prefs empty', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      expect(n.watermarkOpacity, closeTo(0.06, 0.001));
    });

    test('setWatermarkOpacity persists and notifies', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      var notifyCount = 0;
      n.addListener(() => notifyCount++);
      await n.setWatermarkOpacity(0.12);
      expect(n.watermarkOpacity, closeTo(0.12, 0.001));
      expect(notifyCount, 1);
    });

    test('setWatermarkOpacity clamps to 0..0.20', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      await n.setWatermarkOpacity(-0.5);
      expect(n.watermarkOpacity, 0.0);
      await n.setWatermarkOpacity(0.99);
      expect(n.watermarkOpacity, closeTo(0.20, 0.001));
    });

    test('setWatermarkOpacity no-ops when value unchanged', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      var notifyCount = 0;
      n.addListener(() => notifyCount++);
      await n.setWatermarkOpacity(0.06);
      expect(notifyCount, 0);
    });

    test('watermarkOpacity persists across reload', () async {
      SharedPreferences.setMockInitialValues({});
      final n1 = SettingsNotifier();
      await n1.load();
      await n1.setWatermarkOpacity(0.09);
      final n2 = SettingsNotifier();
      await n2.load();
      expect(n2.watermarkOpacity, closeTo(0.09, 0.001));
    });
  });

  group('endCountsOxygen', () {
    test('defaults to true when prefs empty', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      expect(n.endCountsOxygen, isTrue);
    });

    test('setEndCountsOxygen flips and notifies', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      var notifyCount = 0;
      n.addListener(() => notifyCount++);
      await n.setEndCountsOxygen(false);
      expect(n.endCountsOxygen, isFalse);
      expect(notifyCount, 1);
    });

    test('setEndCountsOxygen no-ops on identical', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      var notifyCount = 0;
      n.addListener(() => notifyCount++);
      await n.setEndCountsOxygen(true);
      expect(notifyCount, 0);
    });

    test('endCountsOxygen persists across reload', () async {
      SharedPreferences.setMockInitialValues({});
      final n1 = SettingsNotifier();
      await n1.load();
      await n1.setEndCountsOxygen(false);
      final n2 = SettingsNotifier();
      await n2.load();
      expect(n2.endCountsOxygen, isFalse);
    });
  });
}
