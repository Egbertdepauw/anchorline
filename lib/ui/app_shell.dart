import 'package:flutter/material.dart';

import '../data/db/dive_dao.dart';
import 'notifiers/dive_list_notifier.dart';
import 'screens/dive_list_screen.dart';
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
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _diveListNotifier = DiveListNotifier(widget.diveDao);
    _screens = [
      DiveListScreen(notifier: _diveListNotifier, diveDao: widget.diveDao),
      const PlaceholderScreen(title: 'Import from dive computer', icon: Icons.bluetooth),
      const PlaceholderScreen(title: 'Equipment', icon: Icons.build_outlined),
      const PlaceholderScreen(title: 'Settings', icon: Icons.settings_outlined),
    ];
  }

  @override
  void dispose() {
    _diveListNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CCRLog')),
      body: IndexedStack(index: _currentIndex, children: _screens),
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
