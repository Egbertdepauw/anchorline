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

  group('tissueHeatmapExpanded', () {
    test('defaults to false when prefs empty', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      expect(n.tissueHeatmapExpanded, isFalse);
    });

    test('setTissueHeatmapExpanded flips and notifies', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      var notifyCount = 0;
      n.addListener(() => notifyCount++);
      await n.setTissueHeatmapExpanded(true);
      expect(n.tissueHeatmapExpanded, isTrue);
      expect(notifyCount, 1);
    });

    test('setTissueHeatmapExpanded no-ops on identical value', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      var notifyCount = 0;
      n.addListener(() => notifyCount++);
      await n.setTissueHeatmapExpanded(false);
      expect(notifyCount, 0);
    });

    test('tissueHeatmapExpanded persists across reload', () async {
      SharedPreferences.setMockInitialValues({});
      final n1 = SettingsNotifier();
      await n1.load();
      await n1.setTissueHeatmapExpanded(true);
      final n2 = SettingsNotifier();
      await n2.load();
      expect(n2.tissueHeatmapExpanded, isTrue);
    });
  });

  group('bailout config', () {
    test('bailoutSacBottom defaults to 30', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      expect(n.bailoutSacBottom, 30);
    });

    test('bailoutSacBottom clamps to 10..60', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      await n.setBailoutSacBottom(5);
      expect(n.bailoutSacBottom, 10);
      await n.setBailoutSacBottom(100);
      expect(n.bailoutSacBottom, 60);
    });

    test('bailoutSacDeco defaults to 20', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      expect(n.bailoutSacDeco, 20);
    });

    test('bailoutSacDeco clamps to 10..60', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      await n.setBailoutSacDeco(2);
      expect(n.bailoutSacDeco, 10);
      await n.setBailoutSacDeco(99);
      expect(n.bailoutSacDeco, 60);
    });

    test('bailoutAscentRateFast defaults to 18, clamps 3..30', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      expect(n.bailoutAscentRateFast, 18);
      await n.setBailoutAscentRateFast(50);
      expect(n.bailoutAscentRateFast, 30);
      await n.setBailoutAscentRateFast(1);
      expect(n.bailoutAscentRateFast, 3);
    });

    test('bailoutAscentRateSlow defaults to 9, clamps 3..30', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      expect(n.bailoutAscentRateSlow, 9);
      await n.setBailoutAscentRateSlow(0);
      expect(n.bailoutAscentRateSlow, 3);
      await n.setBailoutAscentRateSlow(40);
      expect(n.bailoutAscentRateSlow, 30);
    });

    test('gueDiluentConfig defaults to false, flips', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      expect(n.gueDiluentConfig, isFalse);
      await n.setGueDiluentConfig(true);
      expect(n.gueDiluentConfig, isTrue);
    });

    test('tank68L300Available defaults to false', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      expect(n.tank68L300Available, isFalse);
    });

    test('tank12L300Available defaults to false', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      expect(n.tank12L300Available, isFalse);
    });

    test('bailout fields persist across reload', () async {
      SharedPreferences.setMockInitialValues({});
      final n1 = SettingsNotifier();
      await n1.load();
      await n1.setBailoutSacBottom(40);
      await n1.setBailoutSacDeco(25);
      await n1.setBailoutAscentRateFast(20);
      await n1.setBailoutAscentRateSlow(6);
      await n1.setGueDiluentConfig(true);
      await n1.setTank68L300Available(true);
      await n1.setTank12L300Available(true);
      final n2 = SettingsNotifier();
      await n2.load();
      expect(n2.bailoutSacBottom, 40);
      expect(n2.bailoutSacDeco, 25);
      expect(n2.bailoutAscentRateFast, 20);
      expect(n2.bailoutAscentRateSlow, 6);
      expect(n2.gueDiluentConfig, isTrue);
      expect(n2.tank68L300Available, isTrue);
      expect(n2.tank12L300Available, isTrue);
    });

    test('int fields no-op on identical value', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      var notifyCount = 0;
      n.addListener(() => notifyCount++);
      await n.setBailoutSacBottom(30);
      await n.setBailoutSacDeco(20);
      await n.setBailoutAscentRateFast(18);
      await n.setBailoutAscentRateSlow(9);
      expect(notifyCount, 0);
    });

    test('bool fields no-op on identical value', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      var notifyCount = 0;
      n.addListener(() => notifyCount++);
      await n.setGueDiluentConfig(false);
      await n.setTank68L300Available(false);
      await n.setTank12L300Available(false);
      expect(notifyCount, 0);
    });
  });

  group('vpmbConservatism', () {
    test('defaults to 2 when prefs empty', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      expect(n.vpmbConservatism, 2);
    });

    test('setVpmbConservatism updates value and notifies', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      var notifyCount = 0;
      n.addListener(() => notifyCount++);
      await n.setVpmbConservatism(4);
      expect(n.vpmbConservatism, 4);
      expect(notifyCount, 1);
    });

    test('setVpmbConservatism clamps negatives to 0', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      await n.setVpmbConservatism(-5);
      expect(n.vpmbConservatism, 0);
    });

    test('setVpmbConservatism clamps values > 4 to 4', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      await n.setVpmbConservatism(10);
      expect(n.vpmbConservatism, 4);
    });

    test('setVpmbConservatism no-ops on identical value', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      var notifyCount = 0;
      n.addListener(() => notifyCount++);
      await n.setVpmbConservatism(2);
      expect(notifyCount, 0);
    });

    test('persists across reload', () async {
      SharedPreferences.setMockInitialValues({});
      final n1 = SettingsNotifier();
      await n1.load();
      await n1.setVpmbConservatism(3);
      final n2 = SettingsNotifier();
      await n2.load();
      expect(n2.vpmbConservatism, 3);
    });
  });
}
