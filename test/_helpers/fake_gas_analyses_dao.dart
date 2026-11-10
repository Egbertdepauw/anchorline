/// In-memory [GasAnalysesDaoLike] for widget tests (no PowerSync I/O, so
/// it works under the fake clock of `testWidgets`).
library;

import 'dart:async';

import 'package:ccrlogger/data/db/gas_analyses_dao.dart';

class FakeGasAnalysesDao implements GasAnalysesDaoLike {
  FakeGasAnalysesDao({
    this.cylinders = const [],
    List<GasAnalysis>? analyses,
  }) : analyses = analyses ?? [];

  final List<CylinderChoice> cylinders;
  final List<GasAnalysis> analyses;
  final List<NewGasAnalysis> added = [];
  final List<(String, NewGasAnalysis)> addedFromBridge = [];
  final List<String> deleted = [];
  final List<(String, GasAnalysisEdit)> updated = [];
  final List<(String, bool)> signoffChanges = [];
  final _changes = StreamController<void>.broadcast();

  @override
  Future<String> add(NewGasAnalysis a) async {
    added.add(a);
    final id = 'a${added.length}';
    analyses.add(
        GasAnalysis.fromNew(id, a, cylinderLabel: _labelOf(a.cylinderId)));
    _changes.add(null);
    return id;
  }

  /// Like the DAO: refuses an id that is already there, deleted ones
  /// included. Every call is recorded in [addedFromBridge].
  @override
  Future<bool> addFromBridge(String id, NewGasAnalysis a) async {
    addedFromBridge.add((id, a));
    if (analyses.any((x) => x.id == id) || deleted.contains(id)) return false;
    analyses.add(
        GasAnalysis.fromNew(id, a, cylinderLabel: _labelOf(a.cylinderId)));
    _changes.add(null);
    return true;
  }

  String? _labelOf(String? cylinderId) {
    final cyl = cylinders.where((c) => c.id == cylinderId);
    return cyl.isEmpty ? null : cyl.first.label;
  }

  @override
  Future<List<GasAnalysis>> list({String? cylinderId}) async {
    final out = analyses
        .where((a) => !deleted.contains(a.id))
        .where((a) => cylinderId == null || a.cylinderId == cylinderId)
        .toList()
      ..sort((a, b) => b.analysedAt.compareTo(a.analysedAt));
    return out;
  }

  @override
  Future<void> update(String id, GasAnalysisEdit edit) async {
    updated.add((id, edit));
    final i = analyses.indexWhere((a) => a.id == id);
    if (i < 0) return;
    final edited = analyses[i].applyEdit(edit);
    // The DAO joins the label again on read, so the fake does too when the
    // cylinder changed (applyEdit drops the old label then).
    analyses[i] = edited.cylinderId == analyses[i].cylinderId
        ? edited
        : _withLabel(edited, _labelOf(edited.cylinderId));
    _changes.add(null);
  }

  @override
  Future<void> setNeedsSignoff(String id, bool needsSignoff) async {
    signoffChanges.add((id, needsSignoff));
    final i = analyses.indexWhere((a) => a.id == id);
    if (i < 0) return;
    analyses[i] = analyses[i].withNeedsSignoff(needsSignoff);
    _changes.add(null);
  }

  /// [a] with the joined cylinder label replaced.
  static GasAnalysis _withLabel(GasAnalysis a, String? cylinderLabel) =>
      GasAnalysis(
        id: a.id,
        cylinderId: a.cylinderId,
        cylinderLabel: cylinderLabel,
        cylinderDeleted: a.cylinderDeleted,
        analysedBy: a.analysedBy,
        analysedAt: a.analysedAt,
        o2Percent: a.o2Percent,
        hePercent: a.hePercent,
        fillPressureBar: a.fillPressureBar,
        tempC: a.tempC,
        baroHpa: a.baroHpa,
        modPpo2s: a.modPpo2s,
        stable: a.stable,
        notes: a.notes,
        targetO2Percent: a.targetO2Percent,
        targetHePercent: a.targetHePercent,
        gasRole: a.gasRole,
        needsSignoff: a.needsSignoff,
        captureSource: a.captureSource,
        bridgeRecordId: a.bridgeRecordId,
        analysedFor: a.analysedFor,
      );

  @override
  Future<void> softDelete(String id) async {
    deleted.add(id);
    _changes.add(null);
  }

  @override
  Future<List<CylinderChoice>> listCylinderChoices() async => cylinders;

  @override
  Stream<void> watchChanges() => _changes.stream;
}
