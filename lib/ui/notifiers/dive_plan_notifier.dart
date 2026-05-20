/// Editor state for the Dive Plan tab.
///
/// Holds the editable plan, the resolved settings (defaults + overrides),
/// and the most recent [PlanResult]. Edits are debounced-written to the
/// `dive_plans` draft row and trigger a synchronous re-compute.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../analysis/bailout/tank_recommender.dart';
import '../../analysis/planner/plan_result.dart';
import '../../analysis/planner/plan_runner.dart';
import '../../data/db/dive_plans_dao.dart' show DivePlanDraft, SavedDivePlan;
import '../../data/db/dive_plans_dao_api.dart';
import '../../data/models/dive_plan.dart';
import 'settings_notifier.dart';

/// Result of [DivePlanNotifier.save] — tells the screen whether the
/// save overwrote an existing saved row or created a new one, so the
/// snackbar can phrase itself appropriately.
class SavedPlanWriteResult {
  const SavedPlanWriteResult._({
    required this.id,
    required this.name,
    required this.wasOverwrite,
  });
  factory SavedPlanWriteResult.overwritten({
    required String id,
    required String name,
  }) =>
      SavedPlanWriteResult._(id: id, name: name, wasOverwrite: true);
  factory SavedPlanWriteResult.created({
    required String id,
    required String name,
  }) =>
      SavedPlanWriteResult._(id: id, name: name, wasOverwrite: false);

  final String id;
  final String name;
  final bool wasOverwrite;
}

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
  // In-memory only — the draft row has `name IS NULL` by definition
  // (that's the draft / saved discriminator). When the diver promotes
  // the draft to a saved plan via [saveAs], we copy the field here too
  // so the inline label stays put after the snackbar.
  String? _planName;

  // Saved-plan provenance. When a saved plan is loaded (or just saved),
  // we record its id + the name it had at that moment so the screen
  // can decide between "overwrite the existing saved row" (id known +
  // name unchanged) and "save-as-new" (no id, or name diverged).
  String? _currentSavedPlanId;
  String? _savedPlanName;

  // Serialized snapshot of the plan as it was last persisted to a saved
  // row. Compared against the live snapshot to derive [isDirty]. Null
  // means "never saved" — in that case dirtiness is "any content exists".
  String? _savedBaseline;

  DivePlanMode get mode => _mode;
  List<DivePlanGas> get gases => List.unmodifiable(_gases);
  List<DivePlanSegment> get segments => List.unmodifiable(_segments);
  List<DivePlanBailoutBottle> get bailout => List.unmodifiable(_bailout);
  DivePlanSettings get overrides => _overrides;
  String? get notes => _notes;
  String? get planName => _planName;
  String? get currentSavedPlanId => _currentSavedPlanId;

  /// True when the editor holds changes that are not yet captured in a
  /// saved plan row. Drives the "unsaved changes" pip in the app bar
  /// and decides whether the Save button overwrites or creates new.
  bool get isDirty {
    final live = _serializeForBaseline();
    final baseline = _savedBaseline ?? _serializeForBaseline(
      mode: DivePlanMode.cc,
      gases: const [],
      segments: const [],
      bailout: const [],
      overrides: const DivePlanSettings(),
      notes: null,
    );
    return live != baseline;
  }

  /// True when the inline plan name matches the name the currently-
  /// loaded saved plan was saved under. False either when there is no
  /// loaded plan, or when the user has renamed the plan inline.
  bool get nameMatchesSavedPlan =>
      _currentSavedPlanId != null && _planName == _savedPlanName;

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
      _planName = draft.planName;
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

  void replaceBailoutBottle(int idx, DivePlanBailoutBottle b) {
    _bailout = [..._bailout]..[idx] = b;
    _markDirty();
  }

  void setOverrides(DivePlanSettings s) {
    _overrides = s;
    _markDirty();
  }

  /// Switches the plan between closed-circuit (default) and open-circuit
  /// computation. OC plans pass every gas in the list to the deco
  /// planner so it can MultiDeco-style auto-switch at each safe depth;
  /// CC plans restrict deco to the active diluent (see [runPlan]).
  void setMode(DivePlanMode m) {
    if (_mode == m) return;
    _mode = m;
    _markDirty();
  }

  /// Sets the inline plan-name label. Does NOT trigger a recompute or a
  /// draft write — the name is purely UI state until [saveAs] persists it.
  void setPlanName(String? name) {
    final trimmed = name == null || name.trim().isEmpty ? null : name.trim();
    if (trimmed == _planName) return;
    _planName = trimmed;
    notifyListeners();
  }

  /// Smart-save: if a saved plan is currently loaded AND its name
  /// hasn't been changed, overwrite that row. Otherwise create a new
  /// saved row. Returns the saved plan record.
  Future<SavedPlanWriteResult> save() async {
    final name = _planName;
    if (name == null || name.isEmpty) {
      throw StateError('Cannot save a plan without a name.');
    }
    if (nameMatchesSavedPlan) {
      await _overwriteCurrentSaved(name);
      return SavedPlanWriteResult.overwritten(id: _currentSavedPlanId!, name: name);
    }
    final saved = await _saveAsNewInternal(name);
    return SavedPlanWriteResult.created(id: saved.id, name: saved.name);
  }

  /// Promotes the current draft to a NEW saved plan with [name]. Useful
  /// when the diver explicitly wants a separate copy (Save-as flow);
  /// most callers should go through [save] instead.
  Future<void> saveAs(String name) async {
    await _saveAsNewInternal(name);
  }

  Future<SavedDivePlan> _saveAsNewInternal(String name) async {
    // Cancel pending debounced draft write and flush the current
    // in-memory snapshot synchronously — the DAO's saveAs reads from
    // the draft row, so it has to exist with current state before we
    // promote it.
    _saveTimer?.cancel();
    await dao.upsertDraft(_snapshot());
    final saved = await dao.saveAs(name: name);
    _planName = name;
    _currentSavedPlanId = saved.id;
    _savedPlanName = name;
    _savedBaseline = _serializeForBaseline();
    // The DAO deletes the draft row as part of promotion. Re-create it
    // so the editor's state survives a subsequent app restart.
    await dao.upsertDraft(_snapshot());
    notifyListeners();
    return saved;
  }

  Future<void> _overwriteCurrentSaved(String name) async {
    final id = _currentSavedPlanId!;
    _saveTimer?.cancel();
    await dao.upsertDraft(_snapshot());
    await dao.updateSaved(id: id, draft: _snapshot(), name: name);
    _planName = name;
    _savedPlanName = name;
    _savedBaseline = _serializeForBaseline();
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
    _planName = draft.planName;
    _currentSavedPlanId = id;
    _savedPlanName = draft.planName;
    _savedBaseline = _serializeForBaseline();
    await dao.upsertDraft(_snapshot());
    _recompute();
    notifyListeners();
  }

  Future<void> newPlan() async {
    await dao.clearDraft();
    _clearAll();
    // Baseline-of-emptiness = the cleared snapshot. Otherwise an empty
    // plan would report isDirty=false only intermittently depending on
    // whether we'd saved something earlier.
    _savedBaseline = _serializeForBaseline();
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
    _planName = null;
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

  /// Deterministic JSON string for dirty-comparison. Excludes [planName]
  /// — the name is not part of the plan content; renaming alone counts
  /// as a dirty change at the save-flow level, tracked separately via
  /// [nameMatchesSavedPlan].
  String _serializeForBaseline({
    DivePlanMode? mode,
    List<DivePlanGas>? gases,
    List<DivePlanSegment>? segments,
    List<DivePlanBailoutBottle>? bailout,
    DivePlanSettings? overrides,
    String? notes,
  }) =>
      jsonEncode({
        'mode': (mode ?? _mode).name,
        'gases': (gases ?? _gases).map((g) => g.toJson()).toList(),
        'segments': (segments ?? _segments).map((s) => s.toJson()).toList(),
        'bailout': (bailout ?? _bailout).map((b) => b.toJson()).toList(),
        'settings': (overrides ?? _overrides).toJson(),
        'notes': notes ?? _notes,
      });

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
      // ascentRateMpm is the legacy single-rate parameter; the planner
      // also receives separate fast (transit / "Opgang") + slow (between
      // deco stops) rates that match MultiDeco / Petrel conventions.
      ascentRateMpm:
          _overrides.ascentRateMpm ?? settings.bailoutAscentRateSlow,
      ascentRateFastMpm: settings.bailoutAscentRateFast,
      ascentRateSlowMpm: settings.bailoutAscentRateSlow,
      descentRateMpm: _overrides.descentRateMpm ?? 18,
      bottomSetpoint:
          _overrides.bottomSetpoint ?? settings.plannerBottomSetpoint,
      ascentSetpoint:
          _overrides.ascentSetpoint ?? settings.plannerAscentSetpoint,
      decoSetpoint: _overrides.decoSetpoint ?? settings.plannerDecoSetpoint,
      lastStopDepthMeters:
          _overrides.lastStopDepthMeters ?? settings.plannerLastStopDepthMeters,
      decoSwitchDepthMeters: _overrides.decoSwitchDepthMeters ??
          settings.plannerDecoSwitchDepthMeters,
      ocSacLPerMin: _overrides.ocSac ?? settings.plannerOcSac,
      availableTanks: tankCatalogue,
    );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
