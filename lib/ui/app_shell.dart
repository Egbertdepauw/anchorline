import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/db/database.dart';
import '../data/db/dive_dao.dart';
import '../data/db/equipment_dao.dart';
import '../data/db/import_state_dao.dart';
import 'notifiers/dive_list_notifier.dart';
import 'notifiers/import_notifier.dart';
import 'screens/dive_list_screen.dart';
import 'screens/equipment/equipment_landing_screen.dart';
import 'screens/import_screen.dart';
import 'screens/placeholder_screen.dart';

class AppShell extends StatefulWidget {
  final AppDatabase db;

  const AppShell({super.key, required this.db});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  late final DiveDao _diveDao;
  late final ImportStateDao _importStateDao;
  late final EquipmentDao _equipmentDao;
  late final DiveListNotifier _diveListNotifier;
  late final ImportNotifier _importNotifier;

  @override
  void initState() {
    super.initState();
    _diveDao = DiveDao(widget.db);
    _importStateDao = ImportStateDao(widget.db);
    _equipmentDao = EquipmentDao(widget.db);
    _diveListNotifier = DiveListNotifier(_diveDao);
    _importNotifier = ImportNotifier(
      dao: _diveDao,
      importStateDao: _importStateDao,
      equipmentDao: _equipmentDao,
      useMock: kDebugMode,
    );
  }

  @override
  void dispose() {
    _diveListNotifier.dispose();
    _importNotifier.dispose();
    super.dispose();
  }

  void _onViewDives() {
    setState(() => _currentIndex = 0);
    _diveListNotifier.loadDives();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CCRLog')),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          DiveListScreen(notifier: _diveListNotifier, diveDao: _diveDao),
          ImportScreen(notifier: _importNotifier, onViewDives: _onViewDives),
          EquipmentLandingScreen(dao: _equipmentDao, diveDao: _diveDao),
          const PlaceholderScreen(title: 'Settings', icon: Icons.settings_outlined),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.scuba_diving), label: 'Dives'),
          BottomNavigationBarItem(icon: Icon(Icons.bluetooth), label: 'Import'),
          BottomNavigationBarItem(icon: Icon(Icons.build_outlined), label: 'Equipment'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}
