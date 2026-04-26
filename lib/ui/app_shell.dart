import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/db/dive_dao.dart';
import 'notifiers/dive_list_notifier.dart';
import 'notifiers/import_notifier.dart';
import 'screens/dive_list_screen.dart';
import 'screens/import_screen.dart';
import 'screens/placeholder_screen.dart';

class AppShell extends StatefulWidget {
  final DiveDao diveDao;

  const AppShell({super.key, required this.diveDao});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  late final DiveListNotifier _diveListNotifier;
  late final ImportNotifier _importNotifier;

  @override
  void initState() {
    super.initState();
    _diveListNotifier = DiveListNotifier(widget.diveDao);
    _importNotifier = ImportNotifier(dao: widget.diveDao, useMock: kDebugMode);
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
          DiveListScreen(notifier: _diveListNotifier, diveDao: widget.diveDao),
          ImportScreen(notifier: _importNotifier, onViewDives: _onViewDives),
          const PlaceholderScreen(title: 'Equipment', icon: Icons.build_outlined),
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
