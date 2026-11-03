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
  final List<String> deleted = [];
  final List<(String, GasAnalysisEdit)> updated = [];
  final _changes = StreamController<void>.broadcast();

  @override
  Future<String> add(NewGasAnalysis a) async {
    added.add(a);
    final id = 'a${added.length}';
    final cyl = cylinders.where((c) => c.id == a.cylinderId);
    analyses.add(GasAnalysis.fromNew(id, a,
        cylinderLabel: cyl.isEmpty ? null : cyl.first.label));
    _changes.add(null);
    return id;
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
    analyses[i] = analyses[i].applyEdit(edit);
    _changes.add(null);
  }

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
