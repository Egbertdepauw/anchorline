/// Editor state for the Gas Blend tab.
///
/// Holds the editable current-cylinder / target-cylinder / top-off
/// inputs and the latest [BlendResult]. Every edit triggers a
/// synchronous recompute.
///
/// Blend drafts are session-scoped (we don't save them across app
/// restarts), with one exception: the target mix and pressure are kept on
/// the device (SharedPreferences, never synced), so the inputs start from
/// the last target. Which blends still wait for an analysis is not kept
/// here: that is the open blends (#112), which sync.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../analysis/blending/gas_blender.dart';
import '../../analysis/open_blend_match.dart';
import '../../data/models/gas_analysis.dart';
import '../../data/models/open_blend.dart';
import 'settings_notifier.dart';

class BlendNotifier extends ChangeNotifier {
  BlendNotifier({required this.settings}) {
    settings.addListener(_onSettingsChanged);
    _syncDefaultsFromSettings();
    _recompute();
  }

  static const _kTargetO2 = 'blend_target_o2';
  static const _kTargetHe = 'blend_target_he';
  static const _kTargetPressureBar = 'blend_target_pressure_bar';

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
  // Whether the diver edited the target mix / the target pressure in this
  // session. A loadTarget that finishes after that must not overwrite
  // their edit.
  bool _mixEditedThisSession = false;
  bool _pressureEditedThisSession = false;
  bool _disposed = false;

  // A role the diver chose for the blend being edited; null means "use the
  // guess". Cleared by openBlendSaved.
  GasRole? _roleOverride;

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

  /// The role guessed from the target O2, the water capacity and the
  /// diluent size in Settings.
  RoleGuess get roleGuess => guessBlendRole(
        targetO2Percent: _targetOxygenPercent,
        waterCapacityL: _waterCapacityL,
        diluentMaxL: settings.blendDiluentMaxL,
      );

  /// The role the open blend gets: the diver's choice, else [roleGuess].
  GasRole get role => _roleOverride ?? roleGuess.role;
  bool get roleOverridden => _roleOverride != null;

  // ── Mutations ─────────────────────────────────────────────────────
  // Every setter below is driven by the diver typing or tapping on the
  // Blend tab. A call with the value already held (an echo) returns early.
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
    _mixEditedThisSession = true;
    _markDirty();
    unawaited(_storeTargetMix(_targetOxygenPercent, _targetHeliumPercent));
  }

  void setTargetPressure(double bar) {
    if (_targetPressureBar == bar) return;
    _targetPressureBar = bar.clamp(0, 400);
    _pressureEditedThisSession = true;
    _markDirty();
    unawaited(_storeTargetPressure(_targetPressureBar));
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

  /// Overrides the guessed role for the blend being edited.
  void overrideRole(GasRole r) {
    if (_roleOverride == r) return;
    _roleOverride = r;
    notifyListeners();
  }

  /// The open blend to save for the current inputs.
  NewOpenBlend draftOpenBlend({String? blendedBy, required DateTime now}) {
    final by = blendedBy?.trim();
    return NewOpenBlend(
      target: DesiredMix(_targetOxygenPercent, _targetHeliumPercent),
      targetPressureBar: _targetPressureBar,
      residual: DesiredMix(_currentOxygenPercent, _currentHeliumPercent),
      residualPressureBar: _currentPressureBar,
      topoff: DesiredMix(_topoffOxygenPercent, _topoffHeliumPercent),
      waterCapacityL: _waterCapacityL,
      role: role,
      blendedBy: (by == null || by.isEmpty) ? null : by,
      blendedAt: now,
    );
  }

  /// Call after the open blend was saved: the role override applied to that
  /// blend only.
  void openBlendSaved() {
    if (_roleOverride == null) return;
    _roleOverride = null;
    notifyListeners();
  }

  /// Fills the Blend tab's residual gas from a residual analysis. The
  /// pressure is left alone when [pressureBar] is null.
  void applyResidualAnalysis({
    required double o2Percent,
    required double hePercent,
    double? pressureBar,
  }) {
    setCurrentMix(o2Percent.round(), hePercent.round());
    if (pressureBar != null) setCurrentPressure(pressureBar);
  }

  /// Restores the target saved on this device. Call it once at startup; it
  /// needn't be awaited. Anything the diver changed before it finishes is
  /// kept.
  Future<void> loadTarget() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;

    final o2 = prefs.getInt(_kTargetO2);
    final he = prefs.getInt(_kTargetHe);
    if (!_mixEditedThisSession && o2 != null) {
      _targetOxygenPercent = o2.clamp(1, 100);
      _targetHeliumPercent = (he ?? 0).clamp(0, 99);
    }
    final pressure = prefs.getDouble(_kTargetPressureBar);
    if (!_pressureEditedThisSession && pressure != null) {
      _targetPressureBar = pressure.clamp(0, 400);
    }
    _markDirty();
  }

  // ── Internals ─────────────────────────────────────────────────────
  // Each store writes only the field its setter changed, so a mix edit
  // can't clobber a stored pressure that loadTarget hasn't read yet.
  Future<void> _storeTargetMix(int o2, int he) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kTargetO2, o2);
    await prefs.setInt(_kTargetHe, he);
  }

  Future<void> _storeTargetPressure(double bar) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kTargetPressureBar, bar);
  }

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
    _disposed = true;
    settings.removeListener(_onSettingsChanged);
    super.dispose();
  }
}
