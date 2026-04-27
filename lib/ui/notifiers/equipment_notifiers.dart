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
}
