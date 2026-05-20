/// Editor state for the Gas Blend tab.
///
/// Holds the editable current-cylinder / target-cylinder / top-off
/// inputs and the latest [BlendResult]. Every edit triggers a
/// synchronous recompute; there's no debounced persistence yet because
/// blend drafts are session-scoped (we don't save them across app
/// restarts in v1).
library;

import 'package:flutter/foundation.dart';

import '../../analysis/blending/gas_blender.dart';
import 'settings_notifier.dart';

class BlendNotifier extends ChangeNotifier {
  BlendNotifier({required this.settings}) {
    settings.addListener(_onSettingsChanged);
    _syncDefaultsFromSettings();
    _recompute();
  }

  final SettingsNotifier settings;

  // Current cylinder.
  int _currentOxygenPercent = 21;
  int _currentHeliumPercent = 0;
  double _currentPressureBar = 0;
  double _waterCapacityL = 12;

  // Target.
  int _targetOxygenPercent = 18;
  int _targetHeliumPercent = 45;
  double _targetPressureBar = 230;

  // Top-off.
  int _topoffOxygenPercent = 21;
  int _topoffHeliumPercent = 0;

  // Fill sequence + real-gas defaults come from settings; per-blend
  // overrides live here so the diver can experiment without touching
  // global settings.
  late FillSequence _sequence;
  late bool _useRealGas;

  // Blending temperature (gauge during the fill) + settled
  // temperature (where the cylinder will end up). When they differ
  // the blender adds hot-fill compensation.
  late double _fillTempC;
  late double _settledTempC;

  BlendResult? _result;

  // ── Getters ───────────────────────────────────────────────────────
  int get currentOxygenPercent => _currentOxygenPercent;
  int get currentHeliumPercent => _currentHeliumPercent;
  double get currentPressureBar => _currentPressureBar;
  double get waterCapacityL => _waterCapacityL;
  int get targetOxygenPercent => _targetOxygenPercent;
  int get targetHeliumPercent => _targetHeliumPercent;
  double get targetPressureBar => _targetPressureBar;
  int get topoffOxygenPercent => _topoffOxygenPercent;
  int get topoffHeliumPercent => _topoffHeliumPercent;
  FillSequence get sequence => _sequence;
  bool get useRealGas => _useRealGas;
  double get fillTempC => _fillTempC;
  double get settledTempC => _settledTempC;
  BlendResult? get result => _result;

  // ── Mutations ─────────────────────────────────────────────────────
  void setCurrentMix(int o2, int he) {
    if (_currentOxygenPercent == o2 && _currentHeliumPercent == he) return;
    _currentOxygenPercent = o2.clamp(1, 100);
    _currentHeliumPercent = he.clamp(0, 99);
    _markDirty();
  }

  void setCurrentPressure(double bar) {
    if (_currentPressureBar == bar) return;
    _currentPressureBar = bar.clamp(0, 400);
    _markDirty();
  }

  void setWaterCapacity(double litres) {
    if (_waterCapacityL == litres) return;
    _waterCapacityL = litres.clamp(0.5, 50);
    _markDirty();
  }

  void setTargetMix(int o2, int he) {
    if (_targetOxygenPercent == o2 && _targetHeliumPercent == he) return;
    _targetOxygenPercent = o2.clamp(1, 100);
    _targetHeliumPercent = he.clamp(0, 99);
    _markDirty();
  }

  void setTargetPressure(double bar) {
    if (_targetPressureBar == bar) return;
    _targetPressureBar = bar.clamp(0, 400);
    _markDirty();
  }

  void setTopoff(int o2, int he) {
    if (_topoffOxygenPercent == o2 && _topoffHeliumPercent == he) return;
    _topoffOxygenPercent = o2.clamp(1, 100);
    _topoffHeliumPercent = he.clamp(0, 99);
    _markDirty();
  }

  void setSequence(FillSequence s) {
    if (_sequence == s) return;
    _sequence = s;
    _markDirty();
  }

  void setUseRealGas(bool v) {
    if (_useRealGas == v) return;
    _useRealGas = v;
    _markDirty();
  }

  void setFillTempC(double v) {
    final clamped = v.clamp(-20.0, 80.0);
    if (_fillTempC == clamped) return;
    _fillTempC = clamped;
    _markDirty();
  }

  void setSettledTempC(double v) {
    final clamped = v.clamp(-20.0, 80.0);
    if (_settledTempC == clamped) return;
    _settledTempC = clamped;
    _markDirty();
  }

  // ── Internals ─────────────────────────────────────────────────────
  void _markDirty() {
    _recompute();
    notifyListeners();
  }

  void _syncDefaultsFromSettings() {
    _topoffOxygenPercent = settings.blendTopoffOxygenPercent;
    _topoffHeliumPercent = settings.blendTopoffHeliumPercent;
    _sequence = _parseSequence(settings.blendFillSequence);
    _useRealGas = settings.blendUseRealGas;
    _fillTempC = settings.blendFillTempC;
    _settledTempC = settings.blendSettledTempC;
  }

  void _onSettingsChanged() {
    // When the user updates blender defaults / prices in Settings,
    // recompute so the cost panel reflects them. Don't overwrite the
    // user's per-blend overrides of sequence / topoff.
    _recompute();
    notifyListeners();
  }

  void _recompute() {
    _result = planBlend(
      current: CylinderState(
        oxygenPercent: _currentOxygenPercent.toDouble(),
        heliumPercent: _currentHeliumPercent.toDouble(),
        pressureBar: _currentPressureBar,
        waterCapacityL: _waterCapacityL,
      ),
      target: CylinderState(
        oxygenPercent: _targetOxygenPercent.toDouble(),
        heliumPercent: _targetHeliumPercent.toDouble(),
        pressureBar: _targetPressureBar,
        waterCapacityL: _waterCapacityL,
      ),
      topoff: FillSource(
        oxygenPercent: _topoffOxygenPercent.toDouble(),
        heliumPercent: _topoffHeliumPercent.toDouble(),
      ),
      sequence: _sequence,
      useRealGas: _useRealGas,
      prices: BlendPrices(
        oxygenPerLitre: settings.blendOxygenCostPerLitre,
        heliumPerLitre: settings.blendHeliumCostPerLitre,
        airFlatFee: settings.blendAirFlatFee,
      ),
      temperatureKelvin: _fillTempC + 273.15,
      settledTemperatureKelvin: _settledTempC + 273.15,
    );
  }

  static FillSequence _parseSequence(String name) {
    for (final s in FillSequence.values) {
      if (s.name == name) return s;
    }
    return FillSequence.heThenO2ThenTopoff;
  }

  @override
  void dispose() {
    settings.removeListener(_onSettingsChanged);
    super.dispose();
  }
}
