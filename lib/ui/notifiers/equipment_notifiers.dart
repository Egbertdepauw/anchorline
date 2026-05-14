import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../../data/db/database.dart';
import '../../data/db/equipment_dao.dart';

class DiveComputersNotifier extends ChangeNotifier {
  final EquipmentDao _dao;
  StreamSubscription<void>? _watchSub;
  bool _disposed = false;

  DiveComputersNotifier(this._dao) {
    _watchSub = _dao.watchDiveComputers().listen(
      (_) async {
        if (_disposed) return;
        try {
          await load();
        } catch (_) {}
      },
      // Subscription can outlive the underlying psDb during teardown;
      // swallow connection-closed errors instead of letting them surface.
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _watchSub?.cancel();
    super.dispose();
  }

  List<DiveComputer> _computers = [];
  List<DiveComputer> get computers => List.unmodifiable(_computers);

  bool _loading = false;
  bool get loading => _loading;

  Future<void> load() async {
    if (_disposed) return;
    _loading = true;
    notifyListeners();
    final list = await _dao.listDiveComputers();
    if (_disposed) return;
    _computers = list;
    _loading = false;
    notifyListeners();
  }

  Future<void> setNickname(String id, String? nickname) async {
    await _dao.setComputerNickname(id, nickname);
    await load();
  }

  List<PressureMapping> _mappings = [];
  List<PressureMapping> get mappings => List.unmodifiable(_mappings);

  Future<void> loadMappings(String diveComputerId) async {
    if (_disposed) return;
    final list = await _dao.listPressureMappings(diveComputerId);
    if (_disposed) return;
    _mappings = list;
    notifyListeners();
  }

  Future<void> setMapping(
    String diveComputerId,
    int channelIndex,
    String? cylinderId,
  ) async {
    await _dao.setPressureMapping(
      diveComputerId: diveComputerId,
      channelIndex: channelIndex,
      cylinderId: cylinderId,
    );
    await loadMappings(diveComputerId);
  }
}

class CellsNotifier extends ChangeNotifier {
  final EquipmentDao _dao;
  StreamSubscription<void>? _watchSub;
  bool _disposed = false;

  CellsNotifier(this._dao) {
    _watchSub = _dao.watchOxygenCells().listen(
      (_) async {
        if (_disposed) return;
        // Errors from a load triggered by a watch event (e.g. test
        // teardown closing the DB while a write is propagating) must
        // not surface as unhandled async errors.
        try {
          await load();
        } catch (_) {}
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _watchSub?.cancel();
    super.dispose();
  }

  List<OxygenCell> _cells = [];
  List<OxygenCell> get cells => List.unmodifiable(_cells);

  bool _loading = false;
  bool get loading => _loading;

  Future<void> load() async {
    if (_disposed) return;
    _loading = true;
    notifyListeners();
    final list = await _dao.listCells();
    if (_disposed) return;
    _cells = list;
    _loading = false;
    notifyListeners();
  }

  Future<String> addCell({
    required int slot,
    String? label,
    DateTime? installedDate,
    String? notes,
  }) async {
    final id = await _dao.addCell(
      slot: slot,
      label: label,
      installedDate: installedDate,
      notes: notes,
    );
    await load();
    return id;
  }

  Future<void> updateCell(
    String id, {
    int? slot,
    String? label,
    Value<DateTime?>? installedDate,
    String? notes,
  }) async {
    await _dao.updateCell(
      id,
      slot: slot,
      label: label,
      installedDate: installedDate,
      notes: notes,
    );
    await load();
  }

  Future<void> retire(String id) async {
    await _dao.retireCell(id, retiredAt: DateTime.now());
    await load();
  }

  Future<bool> deleteIfUnused(String id) async {
    final ok = await _dao.deleteCellIfUnused(id);
    await load();
    return ok;
  }
}

class ScrubberSessionsNotifier extends ChangeNotifier {
  final EquipmentDao _dao;
  StreamSubscription<void>? _watchSub;
  bool _disposed = false;

  ScrubberSessionsNotifier(this._dao) {
    _watchSub = _dao.watchScrubberSessions().listen(
      (_) async {
        if (_disposed) return;
        try {
          await load();
        } catch (_) {}
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _watchSub?.cancel();
    super.dispose();
  }

  List<ScrubberSession> _sessions = [];
  List<ScrubberSession> get sessions => List.unmodifiable(_sessions);

  Future<void> load() async {
    if (_disposed) return;
    final list = await _dao.listScrubberSessions();
    if (_disposed) return;
    _sessions = list;
    notifyListeners();
  }

  Future<String> addPack({
    required DateTime startedDate,
    String? mediaType,
    String? notes,
  }) async {
    final id = await _dao.addScrubberSession(
      startedDate: startedDate,
      mediaType: mediaType,
      notes: notes,
    );
    await load();
    return id;
  }

  Future<void> updatePack(
    String id, {
    DateTime? startedDate,
    String? mediaType,
    String? notes,
  }) async {
    await _dao.updateScrubberSession(
      id,
      startedDate: startedDate,
      mediaType: mediaType,
      notes: notes,
    );
    await load();
  }

  Future<void> closePack(String id, {required DateTime endedAt}) async {
    await _dao.closeScrubberSession(id, endedAt: endedAt);
    await load();
  }

  Future<void> deletePack(String id) async {
    await _dao.deleteScrubberSession(id);
    await load();
  }
}

class CylindersNotifier extends ChangeNotifier {
  final EquipmentDao _dao;
  StreamSubscription<void>? _watchSub;
  bool _disposed = false;

  CylindersNotifier(this._dao) {
    _watchSub = _dao.watchCylinders().listen(
      (_) async {
        if (_disposed) return;
        try {
          await load();
        } catch (_) {}
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _watchSub?.cancel();
    super.dispose();
  }

  List<Cylinder> _cylinders = [];
  List<Cylinder> get cylinders => List.unmodifiable(_cylinders);

  Future<void> load() async {
    if (_disposed) return;
    final list = await _dao.listCylinders();
    if (_disposed) return;
    _cylinders = list;
    notifyListeners();
  }

  Future<String> add({
    required String label,
    required String role,
    int? bailoutOrder,
    required double volumeLiters,
    required int workingPressureBar,
    String? notes,
  }) async {
    final id = await _dao.addCylinder(
      label: label,
      role: role,
      bailoutOrder: bailoutOrder,
      volumeLiters: volumeLiters,
      workingPressureBar: workingPressureBar,
      notes: notes,
    );
    await load();
    return id;
  }

  Future<void> update(
    String id, {
    String? label,
    String? role,
    int? bailoutOrder,
    double? volumeLiters,
    int? workingPressureBar,
    String? notes,
  }) async {
    await _dao.updateCylinder(
      id,
      label: label,
      role: role,
      bailoutOrder: bailoutOrder,
      volumeLiters: volumeLiters,
      workingPressureBar: workingPressureBar,
      notes: notes,
    );
    await load();
  }

  Future<void> softDelete(String id) async {
    await _dao.softDeleteCylinder(id);
    await load();
  }

  Future<void> seedStandard() async {
    await _dao.seedStandardCcrCylinders();
    await load();
  }
}
