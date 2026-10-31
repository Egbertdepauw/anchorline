import 'package:flutter/material.dart';

import '../../../data/db/dive_annotations_dao.dart';
import '../../../data/db/dive_dao.dart';
import '../../../data/db/equipment_dao.dart';
import '../../../data/db/gas_analyses_dao.dart';
import '../../notifiers/settings_notifier.dart';
import 'cells_list_screen.dart';
import 'cylinders_list_screen.dart';
import 'dive_computers_list_screen.dart';
import 'scrubber_sessions_list_screen.dart';

class EquipmentLandingScreen extends StatefulWidget {
  final EquipmentDao dao;
  final DiveDao diveDao;
  final DiveAnnotationsDao annotationsDao;
  final SettingsNotifier settingsNotifier;

  /// Cylinder analysis log (#111); null hides the per-cylinder entry.
  final GasAnalysesDaoLike? analysesDao;

  const EquipmentLandingScreen({
    super.key,
    required this.dao,
    required this.diveDao,
    required this.annotationsDao,
    required this.settingsNotifier,
    this.analysesDao,
  });

  @override
  State<EquipmentLandingScreen> createState() => _EquipmentLandingScreenState();
}

class _EquipmentLandingScreenState extends State<EquipmentLandingScreen> {
  int _computers = 0;
  int _cells = 0;
  int _scrubbers = 0;
  int _cylinders = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final c = await widget.dao.listDiveComputers();
    final ce = await widget.dao.listCells();
    final s = await widget.dao.listScrubberSessions();
    final cy = await widget.dao.listCylinders();
    if (!mounted) return;
    setState(() {
      _computers = c.length;
      _cells = ce.length;
      _scrubbers = s.length;
      _cylinders = cy.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(
            title: 'Dive Computers',
            count: _computers,
            icon: Icons.bluetooth,
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => DiveComputersListScreen(dao: widget.dao),
              ));
              await _refresh();
            },
          ),
          const SizedBox(height: 12),
          _Card(
            title: 'O2 Cells',
            count: _cells,
            icon: Icons.science_outlined,
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CellsListScreen(
                  dao: widget.dao,
                  diveDao: widget.diveDao,
                  annotationsDao: widget.annotationsDao,
                  settingsNotifier: widget.settingsNotifier,
                ),
              ));
              await _refresh();
            },
          ),
          const SizedBox(height: 12),
          _Card(
            title: 'Scrubbers',
            count: _scrubbers,
            icon: Icons.replay_circle_filled_outlined,
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ScrubberSessionsListScreen(dao: widget.dao),
              ));
              await _refresh();
            },
          ),
          const SizedBox(height: 12),
          _Card(
            title: 'Cylinders',
            count: _cylinders,
            icon: Icons.propane_tank_outlined,
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CylindersListScreen(
                  dao: widget.dao,
                  analysesDao: widget.analysesDao,
                ),
              ));
              await _refresh();
            },
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;
  final VoidCallback onTap;

  const _Card({
    required this.title,
    required this.count,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: Text('$count', style: Theme.of(context).textTheme.titleLarge),
        onTap: onTap,
      ),
    );
  }
}
