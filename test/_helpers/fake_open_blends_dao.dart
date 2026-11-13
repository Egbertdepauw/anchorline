/// In-memory [OpenBlendsDaoLike] for widget tests (no PowerSync I/O, so it
/// works under the fake clock of `testWidgets`). Same semantics as the real
/// DAO: a blend is open when it isn't dismissed and either has no closing
/// analysis or that analysis is in [deletedAnalysisIds].
library;

import 'dart:async';

import 'package:ccrlogger/data/db/open_blends_dao.dart';

class FakeOpenBlendsDao implements OpenBlendsDaoLike {
  FakeOpenBlendsDao({List<OpenBlend>? blends, Set<String>? deletedAnalysisIds})
      : blends = blends ?? [],
        deletedAnalysisIds = deletedAnalysisIds ?? {};

  final List<OpenBlend> blends;

  /// Analyses that were soft-deleted: a blend closed by one is open again.
  final Set<String> deletedAnalysisIds;

  final List<NewOpenBlend> added = [];
  final List<String> dismissed = [];

  /// Blend id to the analysis id that closed it, in call order.
  final Map<String, String> closedBy = {};
  final List<(OpenBlend, String)> closeBlendCalls = [];
  final List<(DesiredMix, String)> closeOldestCalls = [];
  final _changes = StreamController<void>.broadcast();
  int _nextId = 0;

  /// How many times [watchOpen] was called.
  int watchOpenCalls = 0;

  /// When set, [add] awaits it before storing and throws on error.
  Future<void>? addGate;
  Object? addError;

  static String? _blankToNull(String? s) {
    final t = s?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  bool _isOpen(OpenBlend b) {
    if (dismissed.contains(b.id)) return false;
    final by = closedBy[b.id];
    return by == null || deletedAnalysisIds.contains(by);
  }

  List<OpenBlend> get _open {
    final out = blends.where(_isOpen).toList();
    // List.sort isn't stable; the index keeps insertion order on ties.
    final order = {for (var i = 0; i < blends.length; i++) blends[i].id: i};
    out.sort((a, b) {
      final c = a.blendedAt.compareTo(b.blendedAt);
      return c != 0 ? c : order[a.id]!.compareTo(order[b.id]!);
    });
    return out;
  }

  /// Marks [analysisId] deleted, which reopens the blend it closed.
  void deleteAnalysis(String analysisId) {
    deletedAnalysisIds.add(analysisId);
    _changes.add(null);
  }

  @override
  Future<String> add(NewOpenBlend b) async {
    if (addGate != null) await addGate;
    if (addError != null) throw addError!;
    added.add(b);
    var id = 'b${++_nextId}';
    while (blends.any((x) => x.id == id)) {
      id = 'b${++_nextId}';
    }
    blends.add(OpenBlend(
      id: id,
      target: b.target,
      targetPressureBar: b.targetPressureBar,
      residual: b.residual,
      residualPressureBar: b.residualPressureBar,
      topoff: b.topoff,
      waterCapacityL: b.waterCapacityL,
      role: b.role,
      blendedBy: _blankToNull(b.blendedBy),
      blendedAt: b.blendedAt,
    ));
    _changes.add(null);
    return id;
  }

  @override
  Future<List<OpenBlend>> listOpen() async => _open;

  @override
  Stream<List<OpenBlend>> watchOpen() {
    watchOpenCalls++;
    return _watch();
  }

  Stream<List<OpenBlend>> _watch() async* {
    yield _open;
    await for (final _ in _changes.stream) {
      yield _open;
    }
  }

  String? _oldestOpenOf(DesiredMix target) {
    for (final b in _open) {
      if (b.target == target) return b.id;
    }
    return null;
  }

  @override
  Future<bool> closeBlend(OpenBlend b, String analysisId) async {
    closeBlendCalls.add((b, analysisId));
    final id = _open.any((x) => x.id == b.id) ? b.id : _oldestOpenOf(b.target);
    if (id == null) return false;
    closedBy[id] = analysisId;
    _changes.add(null);
    return true;
  }

  @override
  Future<String?> closeOldestOpen(DesiredMix target, String analysisId) async {
    closeOldestCalls.add((target, analysisId));
    final id = _oldestOpenOf(target);
    if (id == null) return null;
    closedBy[id] = analysisId;
    _changes.add(null);
    return id;
  }

  @override
  Future<OpenBlend?> blendClosedBy(String analysisId) async {
    for (final b in blends) {
      if (!dismissed.contains(b.id) && closedBy[b.id] == analysisId) return b;
    }
    return null;
  }

  @override
  Future<void> dismiss(String id) async {
    dismissed.add(id);
    _changes.add(null);
  }
}
