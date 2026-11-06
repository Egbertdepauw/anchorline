/// Editor state for the Gas Blend tab.
///
/// Holds the editable current-cylinder / target-cylinder / top-off
/// inputs and the latest [BlendResult]. Every edit triggers a
/// synchronous recompute.
///
/// Blend drafts are session-scoped (we don't save them across app
/// restarts), with one exception: the target mix and pressure, plus the
/// time of the diver's last edit of any Blend input, are kept on the device
/// (SharedPreferences, never synced). A diver blends a cylinder and
/// analyses it later, often after restarting the app, and the gas analyzer
/// offers the target they just blended to as the desired mix of that
/// analysis (see [BlendNotifier.recentTarget], #114). Any edit counts as
/// using the target, not only an edit of the target itself, because a diver
/// who blends their usual mix only enters the residual gas and pressure.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../analysis/blending/gas_blender.dart';
import '../../data/models/gas_analysis.dart';
import 'settings_notifier.dart';

class BlendNotifier extends ChangeNotifier {
  /// [now] is the clock [recentTarget] measures its 24 h window against;
  /// tests inject their own.
  BlendNotifier({required this.settings, DateTime Function()? now})
      : _now = now ?? DateTime.now {
    settings.addListener(_onSettingsChanged);
    _syncDefaultsFromSettings();
    _recompute();
  }

  static const _kTargetO2 = 'blend_target_o2';
  static const _kTargetHe = 'blend_target_he';
  static const _kTargetPressureBar = 'blend_target_pressure_bar';
  // The time of the last edit of any Blend input, not only the target.
  static const _kLastEditedAt = 'blend_target_edited_at';
  // One blend is one cylinder: set once a complete save used the target,
  // cleared by the next Blend edit.
  static const _kTargetUsed = 'blend_target_used';

  /// How long after the diver last edited a Blend input the target still
  /// counts as "the mix they are blending" for [recentTarget].
  static const _recentTargetWindow = Duration(hours: 24);

  final SettingsNotifier settings;
  final DateTime Function() _now;

  // Current cylinder.
  int _currentOxygenPercent = 21;
  int _currentHeliumPercent = 0;
  double _currentPressureBar = 0;
  double _waterCapacityL = 12;

  // Target.
  int _targetOxygenPercent = 18;
  int _targetHeliumPercent = 45;
  double _targetPressureBar = 230;
  // When the diver last edited any Blend input; null until they have (a
  // fresh install has a default target nobody chose). loadTarget restores
  // it as stored and never resets it.
  DateTime? _lastEditedAt;
  // Whether the diver edited anything / the target mix / the target
  // pressure in this session. A loadTarget that finishes after that must
  // not overwrite their edit, or the edit time.
  bool _editedThisSession = false;
  bool _targetUsed = false;
  bool _mixEditedThisSession = false;
  bool _pressureEditedThisSession = false;
  bool _disposed = false;

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
  // Every setter below is driven by the diver typing or tapping on the
  // Blend tab. A call that changes a value counts as an edit
  // ([_markEdited]); a call with the value already held (an echo) returns
  // early and counts as nothing.
  void setCurrentMix(int o2, int he) {
    if (_currentOxygenPercent == o2 && _currentHeliumPercent == he) return;
    _currentOxygenPercent = o2.clamp(1, 100);
    _currentHeliumPercent = he.clamp(0, 99);
    _markEdited();
    _markDirty();
  }

  void setCurrentPressure(double bar) {
    if (_currentPressureBar == bar) return;
    _currentPressureBar = bar.clamp(0, 400);
    _markEdited();
    _markDirty();
  }

  void setWaterCapacity(double litres) {
    if (_waterCapacityL == litres) return;
    _waterCapacityL = litres.clamp(0.5, 50);
    _markEdited();
    _markDirty();
  }

  void setTargetMix(int o2, int he) {
    if (_targetOxygenPercent == o2 && _targetHeliumPercent == he) return;
    _targetOxygenPercent = o2.clamp(1, 100);
    _targetHeliumPercent = he.clamp(0, 99);
    _mixEditedThisSession = true;
    _markEdited();
    _markDirty();
    unawaited(_storeTargetMix(_targetOxygenPercent, _targetHeliumPercent));
  }

  void setTargetPressure(double bar) {
    if (_targetPressureBar == bar) return;
    _targetPressureBar = bar.clamp(0, 400);
    _pressureEditedThisSession = true;
    _markEdited();
    _markDirty();
    unawaited(_storeTargetPressure(_targetPressureBar));
  }

  void setTopoff(int o2, int he) {
    if (_topoffOxygenPercent == o2 && _topoffHeliumPercent == he) return;
    _topoffOxygenPercent = o2.clamp(1, 100);
    _topoffHeliumPercent = he.clamp(0, 99);
    _markEdited();
    _markDirty();
  }

  void setSequence(FillSequence s) {
    if (_sequence == s) return;
    _sequence = s;
    _markEdited();
    _markDirty();
  }

  void setUseRealGas(bool v) {
    if (_useRealGas == v) return;
    _useRealGas = v;
    _markEdited();
    _markDirty();
  }

  void setFillTempC(double v) {
    final clamped = v.clamp(-20.0, 80.0);
    if (_fillTempC == clamped) return;
    _fillTempC = clamped;
    _markEdited();
    _markDirty();
  }

  void setSettledTempC(double v) {
    final clamped = v.clamp(-20.0, 80.0);
    if (_settledTempC == clamped) return;
    _settledTempC = clamped;
    _markEdited();
    _markDirty();
  }

  /// The target mix, if the diver edited any Blend input (the target, but
  /// also the residual gas, the start pressure, the top-off ...) in the last
  /// 24 h; null otherwise. A target nobody has been blending to, like the
  /// default one on a fresh install, is never returned. An edit time in the
  /// future (the clock moved back) counts as expired.
  DesiredMix? recentTarget() {
    final editedAt = _lastEditedAt;
    if (editedAt == null) return null;
    final age = _now().difference(editedAt);
    if (age.isNegative || age >= _recentTargetWindow) return null;
    return DesiredMix(_targetOxygenPercent, _targetHeliumPercent);
  }

  /// [recentTarget], unless a complete save has already used it. The
  /// analyzer picks from this, so one blend isn't offered to a second
  /// cylinder; the chips keep using [recentTarget].
  DesiredMix? unusedRecentTarget() => _targetUsed ? null : recentTarget();

  /// Marks the current target as used by a saved analysis. The next Blend
  /// edit clears it.
  Future<void> markRecentTargetUsed() async {
    if (_targetUsed) return;
    _targetUsed = true;
    await _storeTargetUsed(true);
  }

  /// Restores the target saved on this device. Call it once at startup; it
  /// needn't be awaited. Anything the diver changed before it finishes is
  /// kept. The edit time is restored as stored, not reset to now.
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
    final editedAtMs = prefs.getInt(_kLastEditedAt);
    if (!_editedThisSession && editedAtMs != null) {
      _lastEditedAt = DateTime.fromMillisecondsSinceEpoch(editedAtMs);
      _targetUsed = prefs.getBool(_kTargetUsed) ?? false;
    }
    _markDirty();
  }

  // ── Internals ─────────────────────────────────────────────────────
  /// Records that the diver just edited a Blend input and keeps the time on
  /// the device. Fire-and-forget, like SettingsNotifier's setters.
  void _markEdited() {
    _editedThisSession = true;
    _targetUsed = false;
    unawaited(_storeTargetUsed(false));
    final editedAt = _lastEditedAt = _now();
    unawaited(_storeEditedAt(editedAt));
  }

  // Each store writes only the field its setter changed, so a mix edit
  // can't clobber a stored pressure that loadTarget hasn't read yet.
  Future<void> _storeEditedAt(DateTime editedAt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastEditedAt, editedAt.millisecondsSinceEpoch);
  }

  Future<void> _storeTargetUsed(bool used) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTargetUsed, used);
  }

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
