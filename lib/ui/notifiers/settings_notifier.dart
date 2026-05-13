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
  static const _kVpmbConservatism = 'vpmb_conservatism';
  static const _kTissueHeatmapExpanded = 'tissue_heatmap_expanded';
  static const _kBailoutSacBottom = 'bailout_sac_bottom';
  static const _kBailoutSacDeco = 'bailout_sac_deco';
  static const _kBailoutAscentRateFast = 'bailout_ascent_fast';
  static const _kBailoutAscentRateSlow = 'bailout_ascent_slow';
  static const _kGueDiluentConfig = 'gue_diluent_config';
  static const _kTank68L300Available = 'tank_6_8l_300_available';
  static const _kTank12L300Available = 'tank_12l_300_available';

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
  int _vpmbConservatism = 2;
  bool _tissueHeatmapExpanded = false;
  int _bailoutSacBottom = 30;
  int _bailoutSacDeco = 20;
  int _bailoutAscentRateFast = 18;
  int _bailoutAscentRateSlow = 9;
  bool _gueDiluentConfig = false;
  bool _tank68L300Available = false;
  bool _tank12L300Available = false;

  bool get useSpeedColoredGraph => _useSpeedColoredGraph;
  Set<TraceType> get visibleTraces => Set.unmodifiable(_visibleTraces);
  MapLayerStyle get mapLayerStyle => _mapLayerStyle;
  double get watermarkOpacity => _watermarkOpacity;
  bool get endCountsOxygen => _endCountsOxygen;
  int get vpmbConservatism => _vpmbConservatism;
  bool get tissueHeatmapExpanded => _tissueHeatmapExpanded;
  int get bailoutSacBottom => _bailoutSacBottom;
  int get bailoutSacDeco => _bailoutSacDeco;
  int get bailoutAscentRateFast => _bailoutAscentRateFast;
  int get bailoutAscentRateSlow => _bailoutAscentRateSlow;
  bool get gueDiluentConfig => _gueDiluentConfig;
  bool get tank68L300Available => _tank68L300Available;
  bool get tank12L300Available => _tank12L300Available;

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
    _tissueHeatmapExpanded =
        prefs.getBool(_kTissueHeatmapExpanded) ?? false;

    final vpmb = prefs.getInt(_kVpmbConservatism);
    if (vpmb != null) {
      _vpmbConservatism = vpmb.clamp(0, 4);
    }

    final sacBottom = prefs.getInt(_kBailoutSacBottom);
    if (sacBottom != null) {
      _bailoutSacBottom = sacBottom.clamp(10, 60);
    }

    final sacDeco = prefs.getInt(_kBailoutSacDeco);
    if (sacDeco != null) {
      _bailoutSacDeco = sacDeco.clamp(10, 60);
    }

    final ascentFast = prefs.getInt(_kBailoutAscentRateFast);
    if (ascentFast != null) {
      _bailoutAscentRateFast = ascentFast.clamp(3, 30);
    }

    final ascentSlow = prefs.getInt(_kBailoutAscentRateSlow);
    if (ascentSlow != null) {
      _bailoutAscentRateSlow = ascentSlow.clamp(3, 30);
    }

    _gueDiluentConfig = prefs.getBool(_kGueDiluentConfig) ?? false;
    _tank68L300Available = prefs.getBool(_kTank68L300Available) ?? false;
    _tank12L300Available = prefs.getBool(_kTank12L300Available) ?? false;

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

  Future<void> setVpmbConservatism(int v) async {
    final clamped = v.clamp(0, 4);
    if (_vpmbConservatism == clamped) return;
    _vpmbConservatism = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kVpmbConservatism, clamped);
  }

  Future<void> setTissueHeatmapExpanded(bool v) async {
    if (_tissueHeatmapExpanded == v) return;
    _tissueHeatmapExpanded = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTissueHeatmapExpanded, v);
  }

  Future<void> setBailoutSacBottom(int v) async {
    final clamped = v.clamp(10, 60);
    if (_bailoutSacBottom == clamped) return;
    _bailoutSacBottom = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kBailoutSacBottom, clamped);
  }

  Future<void> setBailoutSacDeco(int v) async {
    final clamped = v.clamp(10, 60);
    if (_bailoutSacDeco == clamped) return;
    _bailoutSacDeco = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kBailoutSacDeco, clamped);
  }

  Future<void> setBailoutAscentRateFast(int v) async {
    final clamped = v.clamp(3, 30);
    if (_bailoutAscentRateFast == clamped) return;
    _bailoutAscentRateFast = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kBailoutAscentRateFast, clamped);
  }

  Future<void> setBailoutAscentRateSlow(int v) async {
    final clamped = v.clamp(3, 30);
    if (_bailoutAscentRateSlow == clamped) return;
    _bailoutAscentRateSlow = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kBailoutAscentRateSlow, clamped);
  }

  Future<void> setGueDiluentConfig(bool v) async {
    if (_gueDiluentConfig == v) return;
    _gueDiluentConfig = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kGueDiluentConfig, v);
  }

  Future<void> setTank68L300Available(bool v) async {
    if (_tank68L300Available == v) return;
    _tank68L300Available = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTank68L300Available, v);
  }

  Future<void> setTank12L300Available(bool v) async {
    if (_tank12L300Available == v) return;
    _tank12L300Available = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTank12L300Available, v);
  }
}
