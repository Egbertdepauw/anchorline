import 'package:flutter/material.dart';

import '../../../data/db/database.dart';
import '../../../data/db/equipment_dao.dart';
import '../../notifiers/equipment_notifiers.dart';
import 'cell_detail_screen.dart';

class CellsListScreen extends StatefulWidget {
  final EquipmentDao dao;

  const CellsListScreen({super.key, required this.dao});

  @override
  State<CellsListScreen> createState() => _CellsListScreenState();
}

class _CellsListScreenState extends State<CellsListScreen> {
  late final CellsNotifier _n;

  @override
  void initState() {
    super.initState();
    _n = CellsNotifier(widget.dao);
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
      appBar: AppBar(title: const Text('O2 Cells')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final id = await _n.addCell(slot: 1);
          if (!context.mounted) return;
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CellDetailScreen(dao: widget.dao, id: id),
          ));
          await _n.load();
        },
        child: const Icon(Icons.add),
      ),
      body: _n.loading
          ? const Center(child: CircularProgressIndicator())
          : _n.cells.isEmpty
              ? const Center(child: Text('No cells yet'))
              : ListView.builder(
                  itemCount: _n.cells.length,
                  itemBuilder: (_, i) {
                    final c = _n.cells[i];
                    final retired = c.retiredDate != null;
                    return ListTile(
                      title: Text(c.label ?? 'Slot ${c.slot}'),
                      subtitle: Text(_subtitle(c)),
                      trailing: retired
                          ? const Chip(label: Text('Retired'))
                          : null,
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => CellDetailScreen(
                            dao: widget.dao,
                            id: c.id,
                          ),
                        ));
                        await _n.load();
                      },
                    );
                  },
                ),
    );
  }

  String _subtitle(OxygenCell c) {
    final installed = c.installedDate == null
        ? 'install date unset'
        : 'installed ${DateTime.fromMillisecondsSinceEpoch(c.installedDate!).toLocal().toString().split(' ').first}';
    return 'Slot ${c.slot} · $installed';
  }
}
