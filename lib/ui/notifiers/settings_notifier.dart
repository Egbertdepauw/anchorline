import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/map_tile_sources.dart' show MapLayerStyle;
import '../widgets/trace_segmented_bar.dart' show TraceType;

class SettingsNotifier extends ChangeNotifier {
  static const _kSpeedColored = 'use_speed_colored_graph';
  static const _kVisibleTraces = 'visible_traces';
  static const _kMapLayerStyle = 'map_layer_style';
  static const _kWatermarkOpacity = 'watermark_opacity';
  static const _kEndCountsOxygen = 'end_counts_oxygen';

  static const _defaultVisibleTraces = <TraceType>{
    TraceType.ppo2,
    TraceType.setpoint,
    TraceType.deco,
    TraceType.gasChanges,
  };

  bool _useSpeedColoredGraph = true;
  Set<TraceType> _visibleTraces = {..._defaultVisibleTraces};
  MapLayerStyle _mapLayerStyle = MapLayerStyle.normal;
  double _watermarkOpacity = 0.06;
  bool _endCountsOxygen = true;

  bool get useSpeedColoredGraph => _useSpeedColoredGraph;
  Set<TraceType> get visibleTraces => Set.unmodifiable(_visibleTraces);
  MapLayerStyle get mapLayerStyle => _mapLayerStyle;
  double get watermarkOpacity => _watermarkOpacity;
  bool get endCountsOxygen => _endCountsOxygen;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _useSpeedColoredGraph = prefs.getBool(_kSpeedColored) ?? true;

    final tracesList = prefs.getStringList(_kVisibleTraces);
    if (tracesList != null) {
      _visibleTraces = tracesList
          .map((n) =>
              TraceType.values.where((t) => t.name == n).firstOrNull)
          .whereType<TraceType>()
          .toSet();
    }

    final styleName = prefs.getString(_kMapLayerStyle);
    if (styleName != null) {
      _mapLayerStyle = MapLayerStyle.values
              .where((s) => s.name == styleName)
              .firstOrNull ??
          MapLayerStyle.normal;
    }

    final wm = prefs.getDouble(_kWatermarkOpacity);
    if (wm != null) {
      _watermarkOpacity = wm.clamp(0.0, 0.20);
    }

    _endCountsOxygen = prefs.getBool(_kEndCountsOxygen) ?? true;

    notifyListeners();
  }

  Future<void> setUseSpeedColoredGraph(bool v) async {
    if (_useSpeedColoredGraph == v) return;
    _useSpeedColoredGraph = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSpeedColored, v);
  }

  Future<void> toggleTrace(TraceType t) async {
    if (_visibleTraces.contains(t)) {
      _visibleTraces.remove(t);
    } else {
      _visibleTraces.add(t);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kVisibleTraces,
      _visibleTraces.map((t) => t.name).toList(),
    );
  }

  Future<void> setMapLayerStyle(MapLayerStyle s) async {
    if (_mapLayerStyle == s) return;
    _mapLayerStyle = s;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMapLayerStyle, s.name);
  }

  Future<void> setEndCountsOxygen(bool v) async {
    if (_endCountsOxygen == v) return;
    _endCountsOxygen = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEndCountsOxygen, v);
  }

  Future<void> setWatermarkOpacity(double v) async {
    final clamped = v.clamp(0.0, 0.20);
    if (_watermarkOpacity == clamped) return;
    _watermarkOpacity = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kWatermarkOpacity, clamped);
  }
}
