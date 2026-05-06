import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsNotifier extends ChangeNotifier {
  static const _kSpeedColored = 'use_speed_colored_graph';

  bool _useSpeedColoredGraph = true;

  bool get useSpeedColoredGraph => _useSpeedColoredGraph;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _useSpeedColoredGraph = prefs.getBool(_kSpeedColored) ?? true;
    notifyListeners();
  }

  Future<void> setUseSpeedColoredGraph(bool v) async {
    if (_useSpeedColoredGraph == v) return;
    _useSpeedColoredGraph = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSpeedColored, v);
  }
}
