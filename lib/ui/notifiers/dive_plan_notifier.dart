/// Editor state for the Dive Plan tab.
///
/// Holds the editable plan, the resolved settings (defaults + overrides),
/// and the most recent [PlanResult]. Edits are debounced-written to the
/// `dive_plans` draft row and trigger a synchronous re-compute.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../analysis/bailout/tank_recommender.dart';
import '../../analysis/planner/plan_result.dart';
import '../../analysis/planner/plan_runner.dart';
import '../../data/db/dive_plans_dao.dart' show DivePlanDraft;
import '../../data/db/dive_plans_dao_api.dart';
import '../../data/models/dive_plan.dart';
import 'settings_notifier.dart';

class DivePlanNotifier extends ChangeNotifier {
  DivePlanNotifier({required this.dao, required this.settings});

  final DivePlansDaoLike dao;
  final SettingsNotifier settings;

  // ── Editable state ─────────────────────────────────────────────────
  DivePlanMode _mode = DivePlanMode.cc;
  List<DivePlanGas> _gases = [];
  List<DivePlanSegment> _segments = [];
  List<DivePlanBailoutBottle> _bailout = [];
  DivePlanSettings _overrides = const DivePlanSettings();
  String? _notes;

  DivePlanMode get mode => _mode;
  List<DivePlanGas> get gases => List.unmodifiable(_gases);
  List<DivePlanSegment> get segments => List.unmodifiable(_segments);
  List<DivePlanBailoutBottle> get bailout => List.unmodifiable(_bailout);
  DivePlanSettings get overrides => _overrides;
  String? get notes => _notes;

  // ── Compute output ─────────────────────────────────────────────────
  PlanResult? _result;
  PlanResult? get result => _result;

  // ── Debounce ───────────────────────────────────────────────────────
  Timer? _saveTimer;
  static const _saveDelay = Duration(milliseconds: 250);

  Future<void> load() async {
    final draft = await dao.loadDraft();
    if (draft != null) {
      _mode = draft.mode;
      _gases = List.from(draft.gases);
      _segments = List.from(draft.segments);
      _bailout = List.from(draft.bailout);
      _overrides = draft.settings ?? const DivePlanSettings();
      _notes = draft.notes;
    }
    _recompute();
    notifyListeners();
  }

  // ── Mutations ──────────────────────────────────────────────────────
  void addGas(DivePlanGas g) {
    _gases = [..._gases, g];
    _markDirty();
  }

  void removeGas(int idx) {
    _gases = [..._gases]..removeAt(idx);
    _markDirty();
  }

  void replaceGas(int idx, DivePlanGas g) {
    _gases = [..._gases]..[idx] = g;
    _markDirty();
  }

  void addSegment(DivePlanSegment s) {
    _segments = [..._segments, s];
    _markDirty();
  }

  void removeSegment(int idx) {
    _segments = [..._segments]..removeAt(idx);
    _markDirty();
  }

  void replaceSegment(int idx, DivePlanSegment s) {
    _segments = [..._segments]..[idx] = s;
    _markDirty();
  }

  void reorderSegments(int oldIdx, int newIdx) {
    final list = [..._segments];
    final moving = list.removeAt(oldIdx);
    list.insert(newIdx, moving);
    _segments = list;
    _markDirty();
  }

  void addBailoutBottle(DivePlanBailoutBottle b) {
    _bailout = [..._bailout, b];
    _markDirty();
  }

  void removeBailoutBottle(int idx) {
    _bailout = [..._bailout]..removeAt(idx);
    _markDirty();
  }

  void setOverrides(DivePlanSettings s) {
    _overrides = s;
    _markDirty();
  }

  Future<void> saveAs(String name) async {
    await dao.saveAs(name: name);
    _clearAll();
    _recompute();
    notifyListeners();
  }

  Future<void> loadSaved(String id) async {
    final draft = await dao.loadSaved(id);
    if (draft == null) return;
    _mode = draft.mode;
    _gases = List.from(draft.gases);
    _segments = List.from(draft.segments);
    _bailout = List.from(draft.bailout);
    _overrides = draft.settings ?? const DivePlanSettings();
    _notes = draft.notes;
    await dao.upsertDraft(_snapshot());
    _recompute();
    notifyListeners();
  }

  Future<void> newPlan() async {
    await dao.clearDraft();
    _clearAll();
    _recompute();
    notifyListeners();
  }

  // ── Internals ──────────────────────────────────────────────────────

  void _clearAll() {
    _mode = DivePlanMode.cc;
    _gases = [];
    _segments = [];
    _bailout = [];
    _overrides = const DivePlanSettings();
    _notes = null;
  }

  void _markDirty() {
    _recompute();
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, _writeDraft);
  }

  Future<void> _writeDraft() async {
    await dao.upsertDraft(_snapshot());
  }

  DivePlanDraft _snapshot() => DivePlanDraft(
        mode: _mode,
        gases: _gases,
        segments: _segments,
        bailout: _bailout,
        settings: _overrides,
        notes: _notes,
      );

  void _recompute() {
    if (_segments.isEmpty || _gases.isEmpty) {
      _result = null;
      return;
    }
    final tankCatalogue = <TankSpec>[
      kAl40,
      kAl50,
      kAl80,
      if (settings.tank68L300Available) kTank68L300,
      if (settings.tank12L300Available) kTank12L300,
    ];
    _result = runPlan(
      gases: _gases,
      segments: _segments,
      bailout: _bailout,
      mode: _mode,
      gfLow: _overrides.gfLow ?? settings.plannerGfLow,
      gfHigh: _overrides.gfHigh ?? settings.plannerGfHigh,
      useVpmb: _overrides.useVpmb ?? settings.plannerUseVpmb,
      vpmbConservatism:
          _overrides.vpmbConservatism ?? settings.plannerVpmbConservatism,
      ascentRateMpm:
          _overrides.ascentRateMpm ?? settings.bailoutAscentRateSlow,
      descentRateMpm: _overrides.descentRateMpm ?? 18,
      bottomSetpoint:
          _overrides.bottomSetpoint ?? settings.plannerBottomSetpoint,
      ascentSetpoint:
          _overrides.ascentSetpoint ?? settings.plannerAscentSetpoint,
      decoSetpoint: _overrides.decoSetpoint ?? settings.plannerDecoSetpoint,
      lastStopDepthMeters:
          _overrides.lastStopDepthMeters ?? settings.plannerLastStopDepthMeters,
      availableTanks: tankCatalogue,
    );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
