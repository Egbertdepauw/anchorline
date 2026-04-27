import 'package:flutter/foundation.dart';

import '../../data/db/database.dart';
import '../../data/db/equipment_dao.dart';

class DiveComputersNotifier extends ChangeNotifier {
  final EquipmentDao _dao;

  DiveComputersNotifier(this._dao);

  List<DiveComputer> _computers = [];
  List<DiveComputer> get computers => List.unmodifiable(_computers);

  bool _loading = false;
  bool get loading => _loading;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    _computers = await _dao.listDiveComputers();
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
    _mappings = await _dao.listPressureMappings(diveComputerId);
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
  CellsNotifier(this._dao);

  List<OxygenCell> _cells = [];
  List<OxygenCell> get cells => List.unmodifiable(_cells);

  bool _loading = false;
  bool get loading => _loading;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    _cells = await _dao.listCells();
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
    DateTime? installedDate,
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
  ScrubberSessionsNotifier(this._dao);

  List<ScrubberSession> _sessions = [];
  List<ScrubberSession> get sessions => List.unmodifiable(_sessions);

  Future<void> load() async {
    _sessions = await _dao.listScrubberSessions();
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
  CylindersNotifier(this._dao);

  List<Cylinder> _cylinders = [];
  List<Cylinder> get cylinders => List.unmodifiable(_cylinders);

  Future<void> load() async {
    _cylinders = await _dao.listCylinders();
    notifyListeners();
  }

  Future<String> add({
    required String label,
    required String role,
    int? bailoutOrder,
    required double volumeLiters,
    required int workingPressureBar,
    String? gasMix,
    String? notes,
  }) async {
    final id = await _dao.addCylinder(
      label: label,
      role: role,
      bailoutOrder: bailoutOrder,
      volumeLiters: volumeLiters,
      workingPressureBar: workingPressureBar,
      gasMix: gasMix,
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
    String? gasMix,
    String? notes,
  }) async {
    await _dao.updateCylinder(
      id,
      label: label,
      role: role,
      bailoutOrder: bailoutOrder,
      volumeLiters: volumeLiters,
      workingPressureBar: workingPressureBar,
      gasMix: gasMix,
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
