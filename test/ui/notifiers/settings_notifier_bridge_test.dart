import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SettingsNotifier> _loaded() async {
  SharedPreferences.setMockInitialValues({});
  final s = SettingsNotifier();
  await s.load();
  return s;
}

Future<SettingsNotifier> _reloaded() async {
  final s = SettingsNotifier();
  await s.load();
  return s;
}

void main() {
  test('defaults to no bridge and 5 V off', () async {
    final s = await _loaded();
    expect(s.analyzerBridgeId, isNull);
    expect(s.analyzerBridgeName, isNull);
    expect(s.analyzerBridgeVbus, isFalse);
  });

  test('the bridge persists and reads back, under the documented keys',
      () async {
    final s = await _loaded();
    await s.setAnalyzerBridge(id: 'AA:BB', name: 'Anchorline Bridge 1A2B');
    expect(s.analyzerBridgeId, 'AA:BB');
    final reloaded = await _reloaded();
    expect(reloaded.analyzerBridgeId, 'AA:BB');
    expect(reloaded.analyzerBridgeName, 'Anchorline Bridge 1A2B');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('analyzer_bridge_id'), 'AA:BB');
    expect(prefs.getString('analyzer_bridge_name'), 'Anchorline Bridge 1A2B');
  });

  test('forgetting the bridge clears id and name', () async {
    final s = await _loaded();
    await s.setAnalyzerBridge(id: 'AA:BB', name: 'Anchorline Bridge 1A2B');
    await s.forgetAnalyzerBridge();
    expect(s.analyzerBridgeId, isNull);
    final reloaded = await _reloaded();
    expect(reloaded.analyzerBridgeId, isNull);
    expect(reloaded.analyzerBridgeName, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('analyzer_bridge_id'), isFalse);
    expect(prefs.containsKey('analyzer_bridge_name'), isFalse);
  });

  test('the 5 V switch persists', () async {
    final s = await _loaded();
    await s.setAnalyzerBridgeVbus(true);
    expect(s.analyzerBridgeVbus, isTrue);
    expect((await _reloaded()).analyzerBridgeVbus, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('analyzer_bridge_vbus'), isTrue);
    await s.setAnalyzerBridgeVbus(false);
    expect((await _reloaded()).analyzerBridgeVbus, isFalse);
  });
}
