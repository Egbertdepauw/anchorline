import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../analysis/fill_pressure.dart';
import '../theme/app_themes.dart';
import '../widgets/map_tile_sources.dart' show MapLayerStyle;
import '../widgets/trace_segmented_bar.dart' show TraceType;

class SettingsNotifier extends ChangeNotifier {
  static const _kThemeId = 'app_theme';
  static const _kSpeedColored = 'use_speed_colored_graph';
  static const _kVisibleTraces = 'visible_traces';
  static const _kMapLayerStyle = 'map_layer_style';
  static const _kWatermarkOpacity = 'watermark_opacity';
  static const _kEndCountsOxygen = 'end_counts_oxygen';
  static const _kVpmbConservatism = 'vpmb_conservatism';
  static const _kTissueHeatmapExpanded = 'tissue_heatmap_expanded';
  static const _kCellDataGraphExpanded = 'cell_data_graph_expanded';
  static const _kBailoutSacBottom = 'bailout_sac_bottom';
  static const _kBailoutSacDeco = 'bailout_sac_deco';
  static const _kBailoutAscentRateFast = 'bailout_ascent_fast';
  static const _kBailoutAscentRateSlow = 'bailout_ascent_slow';
  static const _kGueDiluentConfig = 'gue_diluent_config';
  static const _kTank68L300Available = 'tank_6_8l_300_available';
  static const _kTank12L300Available = 'tank_12l_300_available';
  static const _kPlannerGfLow = 'planner_gf_low';
  static const _kPlannerGfHigh = 'planner_gf_high';
  static const _kPlannerUseVpmb = 'planner_use_vpmb';
  static const _kPlannerVpmbConservatism = 'planner_vpmb_cons';
  static const _kPlannerBottomSp = 'planner_sp_bottom';
  static const _kPlannerAscentSp = 'planner_sp_ascent';
  static const _kPlannerDecoSp = 'planner_sp_deco';
  static const _kPlannerLastStop = 'planner_last_stop_m';
  static const _kPlannerOcSac = 'planner_oc_sac';
  static const _kPlannerDecoSwitchDepth = 'planner_deco_sp_switch_m';
  static const _kBlendO2CostPerL = 'blend_o2_cost_per_l';
  static const _kBlendHeCostPerL = 'blend_he_cost_per_l';
  static const _kBlendAirFee = 'blend_air_flat_fee';
  static const _kBlendTopoffO2 = 'blend_topoff_o2_pct';
  static const _kBlendTopoffHe = 'blend_topoff_he_pct';
  static const _kBlendSequence = 'blend_fill_sequence';
  static const _kBlendUseRealGas = 'blend_use_real_gas';
  static const _kBlendFillTempC = 'blend_fill_temp_c';
  static const _kBlendSettledTempC = 'blend_settled_temp_c';
  static const _kAnalyzerModPpo2s = 'analyzer_mod_ppo2s';
  static const _kAnalyzerLogOnOk = 'analyzer_log_on_ok';
  static const _kAnalyzerPrintOnOk = 'analyzer_print_on_ok';
  // The name the old save card remembered; read once to start "Your
  // initials" on a device that had none, then removed (see load()).
  static const _kAnalyzerAnalysedBy = 'analyzer_analysed_by';
  static const _kYourInitials = 'your_initials';
  static const _kAnalyzerFillPressureStart = 'analyzer_fill_pressure_start_bar';

  /// Where the analyzer's "Fill pressure" starts when a cylinder is saved.
  static const double kDefaultFillPressureStartBar = 230;
  static const _kLabelUse14 = 'label_use_14_for_deeper_mixes';
  static const _kLabelPrinterId = 'label_printer_id';
  static const _kLabelPrinterName = 'label_printer_name';

  /// Default ppO2 limits the gas analyzer shows a MOD for. 1.1 is the
  /// CCR diluent limit, 1.4 / 1.6 the usual OC bottom / deco limits.
  static const defaultAnalyzerModPpo2s = <double>[1.1, 1.4, 1.6];

  /// Accepted range for an analyzer MOD ppO2 (bar).
  static const double analyzerModPpo2Min = 0.2;
  static const double analyzerModPpo2Max = 2.0;

  static const _defaultVisibleTraces = <TraceType>{
    TraceType.ppo2,
    TraceType.setpoint,
    TraceType.deco,
    TraceType.gasChanges,
  };

  String _themeId = AppThemes.defaultId;
  bool _useSpeedColoredGraph = true;
  Set<TraceType> _visibleTraces = {..._defaultVisibleTraces};
  MapLayerStyle _mapLayerStyle = MapLayerStyle.normal;
  double _watermarkOpacity = 0.06;
  bool _endCountsOxygen = true;
  int _vpmbConservatism = 2;
  bool _tissueHeatmapExpanded = false;
  bool _cellDataGraphExpanded = false;
  int _bailoutSacBottom = 30;
  int _bailoutSacDeco = 20;
  int _bailoutAscentRateFast = 18;
  int _bailoutAscentRateSlow = 9;
  bool _gueDiluentConfig = false;
  bool _tank68L300Available = false;
  bool _tank12L300Available = false;
  int _plannerGfLow = 30;
  int _plannerGfHigh = 85;
  bool _plannerUseVpmb = false;
  int _plannerVpmbConservatism = 2;
  double _plannerBottomSetpoint = 1.3;
  double _plannerAscentSetpoint = 0.7;
  double _plannerDecoSetpoint = 1.4;
  double _plannerLastStopDepthMeters = 6.0;
  int _plannerOcSac = 20;
  // Depth at/above which the deco SP applies. Deeper than this the
  // planner uses the ascent SP. 99 m = "always use deco SP" (no
  // crossover), matching the pre-feature behaviour.
  double _plannerDecoSwitchDepthMeters = 99.0;
  // ── Gas blending ────────────────────────────────────────────────
  // Per-litre cost (at 1 atm) for the O2 and He banks the blender
  // draws from. Air uses a flat fee per fill rather than a metered
  // cost — that's the typical fill-station billing model.
  double _blendOxygenCostPerLitre = 0.05;
  double _blendHeliumCostPerLitre = 0.10;
  double _blendAirFlatFee = 5.0;
  // Default top-off mix. 21/0 = air; pickable in the blender per fill.
  int _blendTopoffOxygenPercent = 21;
  int _blendTopoffHeliumPercent = 0;
  // Default fill sequence — He first by tech-diving convention.
  // Storage is the enum name so an unknown value can fall back safely.
  String _blendFillSequence = 'heThenO2ThenTopoff';
  // Apply Z-factor correction to the top-off bar.
  bool _blendUseRealGas = true;
  // Fill temp = temperature at the fill station (cylinder during
  // blending, typically warm). Settled temp = where the cylinder will
  // end up (storage / dive site). When they differ, the blender adds
  // a hot-fill compensation so the diver fills to a higher gauge that
  // settles to the target on cooldown.
  double _blendFillTempC = 18;
  double _blendSettledTempC = 18;
  // ── Gas analyzer ────────────────────────────────────────────────
  List<double> _analyzerModPpo2s = [...defaultAnalyzerModPpo2s];
  // Log on OK over USB (device-local, never synced).
  bool _analyzerLogOnOk = false;
  bool _analyzerPrintOnOk = true;
  String? _yourInitials;
  double _analyzerFillPressureStartBar = kDefaultFillPressureStartBar;
  // ── Cylinder labels (device-local, never synced) ────────────────
  bool _labelUse14ForDeeperMixes = false;
  String? _labelPrinterId;
  String? _labelPrinterName;

  /// Id of the selected theme. Always a registered id.
  String get themeId => _themeId;

  bool get useSpeedColoredGraph => _useSpeedColoredGraph;
  Set<TraceType> get visibleTraces => Set.unmodifiable(_visibleTraces);
  MapLayerStyle get mapLayerStyle => _mapLayerStyle;
  double get watermarkOpacity => _watermarkOpacity;
  bool get endCountsOxygen => _endCountsOxygen;
  int get vpmbConservatism => _vpmbConservatism;
  bool get tissueHeatmapExpanded => _tissueHeatmapExpanded;
  bool get cellDataGraphExpanded => _cellDataGraphExpanded;
  int get bailoutSacBottom => _bailoutSacBottom;
  int get bailoutSacDeco => _bailoutSacDeco;
  int get bailoutAscentRateFast => _bailoutAscentRateFast;
  int get bailoutAscentRateSlow => _bailoutAscentRateSlow;
  bool get gueDiluentConfig => _gueDiluentConfig;
  bool get tank68L300Available => _tank68L300Available;
  bool get tank12L300Available => _tank12L300Available;
  int get plannerGfLow => _plannerGfLow;
  int get plannerGfHigh => _plannerGfHigh;
  bool get plannerUseVpmb => _plannerUseVpmb;
  int get plannerVpmbConservatism => _plannerVpmbConservatism;
  double get plannerBottomSetpoint => _plannerBottomSetpoint;
  double get plannerAscentSetpoint => _plannerAscentSetpoint;
  double get plannerDecoSetpoint => _plannerDecoSetpoint;
  double get plannerLastStopDepthMeters => _plannerLastStopDepthMeters;
  int get plannerOcSac => _plannerOcSac;
  double get plannerDecoSwitchDepthMeters => _plannerDecoSwitchDepthMeters;
  double get blendOxygenCostPerLitre => _blendOxygenCostPerLitre;
  double get blendHeliumCostPerLitre => _blendHeliumCostPerLitre;
  double get blendAirFlatFee => _blendAirFlatFee;
  int get blendTopoffOxygenPercent => _blendTopoffOxygenPercent;
  int get blendTopoffHeliumPercent => _blendTopoffHeliumPercent;
  String get blendFillSequence => _blendFillSequence;
  bool get blendUseRealGas => _blendUseRealGas;
  double get blendFillTempC => _blendFillTempC;
  double get blendSettledTempC => _blendSettledTempC;

  /// ppO2 limits (bar) the gas analyzer shows a MOD row for, ascending.
  List<double> get analyzerModPpo2s => List.unmodifiable(_analyzerModPpo2s);

  /// Whether an OK press on the SOLO, over a USB cable, saves an analysis
  /// while the analyzer screen is open (issue #113). Off by default.
  bool get analyzerLogOnOk => _analyzerLogOnOk;

  /// Whether an OK press also prints the label, when a label printer is set
  /// up (issue #113). On by default.
  bool get analyzerPrintOnOk => _analyzerPrintOnOk;

  /// The diver's initials (device-local, never synced); they start the
  /// analyzer's "Analysed by" field. Null until set.
  String? get yourInitials => _yourInitials;

  /// The pressure in bar the analyzer's "Fill pressure" field starts at.
  double get analyzerFillPressureStartBar => _analyzerFillPressureStartBar;

  /// Whether a cylinder label uses ppO2 1.4 instead of 1.6 for the MOD of a
  /// bailout/deco mix under 50 % O2.
  bool get labelUse14ForDeeperMixes => _labelUse14ForDeeperMixes;

  /// The label printer saved on this device: its BLE id and the name shown
  /// in Settings. Both null when none is set up.
  String? get labelPrinterId => _labelPrinterId;
  String? get labelPrinterName => _labelPrinterName;

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
    _cellDataGraphExpanded =
        prefs.getBool(_kCellDataGraphExpanded) ?? false;

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

    final pGfLow = prefs.getInt(_kPlannerGfLow);
    if (pGfLow != null) _plannerGfLow = pGfLow.clamp(1, 100);
    final pGfHigh = prefs.getInt(_kPlannerGfHigh);
    if (pGfHigh != null) _plannerGfHigh = pGfHigh.clamp(1, 100);
    _plannerUseVpmb = prefs.getBool(_kPlannerUseVpmb) ?? false;
    final pVpmb = prefs.getInt(_kPlannerVpmbConservatism);
    if (pVpmb != null) _plannerVpmbConservatism = pVpmb.clamp(0, 4);
    final pBottomSp = prefs.getDouble(_kPlannerBottomSp);
    if (pBottomSp != null) {
      _plannerBottomSetpoint = pBottomSp.clamp(0.4, 1.5);
    }
    final pAscentSp = prefs.getDouble(_kPlannerAscentSp);
    if (pAscentSp != null) {
      _plannerAscentSetpoint = pAscentSp.clamp(0.4, 1.5);
    }
    final pDecoSp = prefs.getDouble(_kPlannerDecoSp);
    if (pDecoSp != null) _plannerDecoSetpoint = pDecoSp.clamp(0.4, 1.6);
    final pLast = prefs.getDouble(_kPlannerLastStop);
    if (pLast != null) {
      _plannerLastStopDepthMeters = pLast.clamp(3.0, 9.0);
    }
    final pOcSac = prefs.getInt(_kPlannerOcSac);
    if (pOcSac != null) _plannerOcSac = pOcSac.clamp(5, 60);
    final pDecoSwitch = prefs.getDouble(_kPlannerDecoSwitchDepth);
    if (pDecoSwitch != null) {
      _plannerDecoSwitchDepthMeters = pDecoSwitch.clamp(0.0, 200.0);
    }

    final bO2 = prefs.getDouble(_kBlendO2CostPerL);
    if (bO2 != null) _blendOxygenCostPerLitre = bO2.clamp(0.0, 1000.0);
    final bHe = prefs.getDouble(_kBlendHeCostPerL);
    if (bHe != null) _blendHeliumCostPerLitre = bHe.clamp(0.0, 1000.0);
    final bAir = prefs.getDouble(_kBlendAirFee);
    if (bAir != null) _blendAirFlatFee = bAir.clamp(0.0, 1000.0);
    final bTopO2 = prefs.getInt(_kBlendTopoffO2);
    if (bTopO2 != null) _blendTopoffOxygenPercent = bTopO2.clamp(1, 100);
    final bTopHe = prefs.getInt(_kBlendTopoffHe);
    if (bTopHe != null) _blendTopoffHeliumPercent = bTopHe.clamp(0, 99);
    final bSeq = prefs.getString(_kBlendSequence);
    if (bSeq != null) _blendFillSequence = bSeq;
    _blendUseRealGas = prefs.getBool(_kBlendUseRealGas) ?? true;
    final bFill = prefs.getDouble(_kBlendFillTempC);
    if (bFill != null) _blendFillTempC = bFill.clamp(-20.0, 80.0);
    final bSettled = prefs.getDouble(_kBlendSettledTempC);
    if (bSettled != null) _blendSettledTempC = bSettled.clamp(-20.0, 80.0);
    final aMod = prefs.getStringList(_kAnalyzerModPpo2s);
    if (aMod != null) {
      final parsed = sanitizeAnalyzerModPpo2s(
          aMod.map(double.tryParse).whereType<double>());
      if (parsed.isNotEmpty) _analyzerModPpo2s = parsed;
    }
    _analyzerLogOnOk = prefs.getBool(_kAnalyzerLogOnOk) ?? false;
    _analyzerPrintOnOk = prefs.getBool(_kAnalyzerPrintOnOk) ?? true;
    _yourInitials = _initialsOrNull(prefs.getString(_kYourInitials));
    final rememberedName = prefs.getString(_kAnalyzerAnalysedBy);
    if (rememberedName != null) {
      // Upgrade, once: the name remembered by the old save card becomes the
      // initials, unless they are set already. The old key goes, so
      // initials cleared later stay cleared.
      final migrated = _initialsOrNull(rememberedName);
      if (_yourInitials == null && migrated != null) {
        _yourInitials = migrated;
        await prefs.setString(_kYourInitials, migrated);
      }
      await prefs.remove(_kAnalyzerAnalysedBy);
    }
    _analyzerFillPressureStartBar =
        prefs.getDouble(_kAnalyzerFillPressureStart) ??
            kDefaultFillPressureStartBar;
    _labelUse14ForDeeperMixes = prefs.getBool(_kLabelUse14) ?? false;
    _labelPrinterId = prefs.getString(_kLabelPrinterId);
    _labelPrinterName = prefs.getString(_kLabelPrinterName);

    // `get` rather than `getString`: a value of the wrong type must fall
    // back to the default, not throw before the first frame.
    final storedTheme = prefs.get(_kThemeId);
    _themeId = AppThemes.byId(storedTheme is String ? storedTheme : null).id;

    notifyListeners();
  }

  Future<void> setThemeId(String id) async {
    final resolved = AppThemes.byId(id).id;
    if (_themeId == resolved) return;
    _themeId = resolved;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeId, resolved);
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

  Future<void> setCellDataGraphExpanded(bool v) async {
    if (_cellDataGraphExpanded == v) return;
    _cellDataGraphExpanded = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCellDataGraphExpanded, v);
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

  Future<void> setPlannerGfLow(int v) async {
    final clamped = v.clamp(1, 100);
    if (_plannerGfLow == clamped) return;
    _plannerGfLow = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPlannerGfLow, clamped);
  }

  Future<void> setPlannerGfHigh(int v) async {
    final clamped = v.clamp(1, 100);
    if (_plannerGfHigh == clamped) return;
    _plannerGfHigh = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPlannerGfHigh, clamped);
  }

  Future<void> setPlannerUseVpmb(bool v) async {
    if (_plannerUseVpmb == v) return;
    _plannerUseVpmb = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPlannerUseVpmb, v);
  }

  Future<void> setPlannerVpmbConservatism(int v) async {
    final clamped = v.clamp(0, 4);
    if (_plannerVpmbConservatism == clamped) return;
    _plannerVpmbConservatism = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPlannerVpmbConservatism, clamped);
  }

  Future<void> setPlannerBottomSetpoint(double v) async {
    final clamped = v.clamp(0.4, 1.5);
    if (_plannerBottomSetpoint == clamped) return;
    _plannerBottomSetpoint = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPlannerBottomSp, clamped);
  }

  Future<void> setPlannerAscentSetpoint(double v) async {
    final clamped = v.clamp(0.4, 1.5);
    if (_plannerAscentSetpoint == clamped) return;
    _plannerAscentSetpoint = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPlannerAscentSp, clamped);
  }

  Future<void> setPlannerDecoSetpoint(double v) async {
    final clamped = v.clamp(0.4, 1.6);
    if (_plannerDecoSetpoint == clamped) return;
    _plannerDecoSetpoint = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPlannerDecoSp, clamped);
  }

  Future<void> setPlannerLastStopDepthMeters(double v) async {
    final clamped = v.clamp(3.0, 9.0);
    if (_plannerLastStopDepthMeters == clamped) return;
    _plannerLastStopDepthMeters = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPlannerLastStop, clamped);
  }

  Future<void> setPlannerOcSac(int v) async {
    final clamped = v.clamp(5, 60);
    if (_plannerOcSac == clamped) return;
    _plannerOcSac = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPlannerOcSac, clamped);
  }

  Future<void> setPlannerDecoSwitchDepthMeters(double v) async {
    final clamped = v.clamp(0.0, 200.0);
    if (_plannerDecoSwitchDepthMeters == clamped) return;
    _plannerDecoSwitchDepthMeters = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPlannerDecoSwitchDepth, clamped);
  }

  Future<void> setBlendOxygenCostPerLitre(double v) async {
    final clamped = v.clamp(0.0, 1000.0);
    if (_blendOxygenCostPerLitre == clamped) return;
    _blendOxygenCostPerLitre = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kBlendO2CostPerL, clamped);
  }

  Future<void> setBlendHeliumCostPerLitre(double v) async {
    final clamped = v.clamp(0.0, 1000.0);
    if (_blendHeliumCostPerLitre == clamped) return;
    _blendHeliumCostPerLitre = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kBlendHeCostPerL, clamped);
  }

  Future<void> setBlendAirFlatFee(double v) async {
    final clamped = v.clamp(0.0, 1000.0);
    if (_blendAirFlatFee == clamped) return;
    _blendAirFlatFee = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kBlendAirFee, clamped);
  }

  Future<void> setBlendTopoff(int oxygenPercent, int heliumPercent) async {
    final o = oxygenPercent.clamp(1, 100);
    final h = heliumPercent.clamp(0, 99);
    if (_blendTopoffOxygenPercent == o && _blendTopoffHeliumPercent == h) {
      return;
    }
    _blendTopoffOxygenPercent = o;
    _blendTopoffHeliumPercent = h;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kBlendTopoffO2, o);
    await prefs.setInt(_kBlendTopoffHe, h);
  }

  Future<void> setBlendFillSequence(String name) async {
    if (_blendFillSequence == name) return;
    _blendFillSequence = name;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBlendSequence, name);
  }

  Future<void> setBlendUseRealGas(bool v) async {
    if (_blendUseRealGas == v) return;
    _blendUseRealGas = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBlendUseRealGas, v);
  }

  Future<void> setBlendFillTempC(double v) async {
    final clamped = v.clamp(-20.0, 80.0);
    if (_blendFillTempC == clamped) return;
    _blendFillTempC = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kBlendFillTempC, clamped);
  }

  Future<void> setBlendSettledTempC(double v) async {
    final clamped = v.clamp(-20.0, 80.0);
    if (_blendSettledTempC == clamped) return;
    _blendSettledTempC = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kBlendSettledTempC, clamped);
  }

  Future<void> setAnalyzerModPpo2s(Iterable<double> values) async {
    final cleaned = sanitizeAnalyzerModPpo2s(values);
    if (cleaned.isEmpty || listEquals(cleaned, _analyzerModPpo2s)) return;
    _analyzerModPpo2s = cleaned;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kAnalyzerModPpo2s,
      cleaned.map((v) => v.toString()).toList(),
    );
  }

  Future<void> setAnalyzerLogOnOk(bool v) async {
    if (_analyzerLogOnOk == v) return;
    _analyzerLogOnOk = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAnalyzerLogOnOk, v);
  }

  Future<void> setAnalyzerPrintOnOk(bool v) async {
    if (_analyzerPrintOnOk == v) return;
    _analyzerPrintOnOk = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAnalyzerPrintOnOk, v);
  }

  /// [v] trimmed; null when that is blank.
  static String? _initialsOrNull(String? v) {
    final t = v?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  /// Saves the diver's initials, trimmed. Blank means none.
  Future<void> setYourInitials(String? v) async {
    final initials = _initialsOrNull(v);
    if (_yourInitials == initials) return;
    _yourInitials = initials;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (initials == null) {
      await prefs.remove(_kYourInitials);
    } else {
      await prefs.setString(_kYourInitials, initials);
    }
  }

  /// Sets where the analyzer's fill pressure starts. A value that is not a
  /// valid pressure (see [parseFillPressure]) is ignored.
  Future<void> setAnalyzerFillPressureStartBar(double bar) async {
    if (!parseFillPressure(bar.toString()).valid) return;
    if (_analyzerFillPressureStartBar == bar) return;
    _analyzerFillPressureStartBar = bar;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kAnalyzerFillPressureStart, bar);
  }

  Future<void> setLabelUse14ForDeeperMixes(bool v) async {
    if (_labelUse14ForDeeperMixes == v) return;
    _labelUse14ForDeeperMixes = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLabelUse14, v);
  }

  /// Saves the label printer for this device. [id] is the BLE id used to
  /// reconnect; [name] is only for display.
  Future<void> setLabelPrinter({
    required String id,
    required String name,
  }) async {
    if (_labelPrinterId == id && _labelPrinterName == name) return;
    _labelPrinterId = id;
    _labelPrinterName = name;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLabelPrinterId, id);
    await prefs.setString(_kLabelPrinterName, name);
  }

  Future<void> forgetLabelPrinter() async {
    if (_labelPrinterId == null && _labelPrinterName == null) return;
    _labelPrinterId = null;
    _labelPrinterName = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLabelPrinterId);
    await prefs.remove(_kLabelPrinterName);
  }

  /// Drops non-finite and out-of-range values, rounds to 0.01 bar,
  /// de-duplicates and sorts ascending. May return an empty list.
  static List<double> sanitizeAnalyzerModPpo2s(Iterable<double> values) {
    final set = <double>{};
    for (final v in values) {
      if (!v.isFinite) continue;
      if (v < analyzerModPpo2Min || v > analyzerModPpo2Max) continue;
      set.add((v * 100).round() / 100);
    }
    return set.toList()..sort();
  }
}
