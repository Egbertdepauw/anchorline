import 'package:flutter/material.dart';

import '../../../data/db/database.dart';
import '../../../data/db/equipment_dao.dart';
import '../../../data/db/gas_analyses_dao.dart';
import '../../../data/models/equipment.dart';
import '../../notifiers/equipment_notifiers.dart';
import 'cylinder_detail_screen.dart';

class CylindersListScreen extends StatefulWidget {
  final EquipmentDao dao;

  /// Cylinder analysis log (#111), passed through to the detail screen.
  final GasAnalysesDaoLike? analysesDao;

  const CylindersListScreen({super.key, required this.dao, this.analysesDao});

  @override
  State<CylindersListScreen> createState() => _CylindersListScreenState();
}

class _CylindersListScreenState extends State<CylindersListScreen> {
  late final CylindersNotifier _n;

  @override
  void initState() {
    super.initState();
    _n = CylindersNotifier(widget.dao);
    _n.addListener(_onChanged);
    _n.load();
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _n.removeListener(_onChanged);
    _n.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cylinders')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CylinderDetailScreen(dao: widget.dao),
          ));
          if (!context.mounted) return;
          await _n.load();
        },
        child: const Icon(Icons.add),
      ),
      body: _n.cylinders.isEmpty ? _emptyState() : _grouped(),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'No cylinders yet.\nMost CCR rigs use O2 + Diluent + Bailout.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Set up standard CCR cylinders'),
              onPressed: () => _n.seedStandard(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grouped() {
    final groups = <String, List<Cylinder>>{};
    for (final c in _n.cylinders) {
      groups.putIfAbsent(c.role, () => []).add(c);
    }
    final sections = <Widget>[];
    for (final role in CylinderRole.all) {
      final list = groups[role];
      if (list == null || list.isEmpty) continue;
      sections.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(_label(role),
            style: Theme.of(context).textTheme.titleMedium),
      ));
      for (final c in list) {
        sections.add(ListTile(
          title: Text(c.role == CylinderRole.bailout
              ? '#${c.bailoutOrder ?? '?'} · ${c.label}'
              : c.label),
          subtitle: Text(
              '${c.volumeLiters}L @ ${c.workingPressureBar} bar'),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => CylinderDetailScreen(
                dao: widget.dao,
                id: c.id,
                analysesDao: widget.analysesDao,
              ),
            ));
            await _n.load();
          },
        ));
      }
    }
    return ListView(children: sections);
  }

  String _label(String role) {
    switch (role) {
      case CylinderRole.oxygen:
        return 'Oxygen';
      case CylinderRole.diluent:
        return 'Diluent';
      case CylinderRole.bailout:
        return 'Bailout';
      case CylinderRole.offboard:
        return 'Offboard';
    }
    return role;
  }
}
