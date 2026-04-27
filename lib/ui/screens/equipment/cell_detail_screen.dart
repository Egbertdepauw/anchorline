import 'package:flutter/material.dart';

import '../../../data/db/database.dart';
import '../../../data/db/equipment_dao.dart';
import '../../widgets/cell_mv_chart.dart';

class CellDetailScreen extends StatefulWidget {
  final EquipmentDao dao;
  final String id;

  const CellDetailScreen({super.key, required this.dao, required this.id});

  @override
  State<CellDetailScreen> createState() => _CellDetailScreenState();
}

class _CellDetailScreenState extends State<CellDetailScreen> {
  OxygenCell? _cell;
  List<({DateTime date, double mv, String diveId})> _series = const [];
  final _labelCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cell = await widget.dao.getCell(widget.id);
    if (cell == null) return;
    final series = await widget.dao.surfaceMvSeriesForCell(cell.id);
    if (!mounted) return;
    setState(() {
      _cell = cell;
      _series = series;
      _labelCtrl.text = cell.label ?? '';
      _notesCtrl.text = cell.notes ?? '';
    });
  }

  Future<void> _save() async {
    if (_cell == null) return;
    await widget.dao.updateCell(
      _cell!.id,
      label: _labelCtrl.text.trim().isEmpty ? null : _labelCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    await _load();
  }

  Future<void> _retire() async {
    if (_cell == null) return;
    await widget.dao.retireCell(_cell!.id, retiredAt: DateTime.now());
    await _load();
  }

  Future<void> _deleteIfUnused() async {
    if (_cell == null) return;
    final ok = await widget.dao.deleteCellIfUnused(_cell!.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Cell has attributable dives — cannot delete.'),
      ));
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cell')),
      body: _cell == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Slot ${_cell!.slot}',
                    style: Theme.of(context).textTheme.titleMedium),
                if (_cell!.installedDate != null)
                  Text('Installed: '
                      '${DateTime.fromMillisecondsSinceEpoch(_cell!.installedDate!).toLocal().toString().split(' ').first}'),
                if (_cell!.retiredDate != null)
                  Text('Retired: '
                      '${DateTime.fromMillisecondsSinceEpoch(_cell!.retiredDate!).toLocal().toString().split(' ').first}'),
                Text('Dives: ${_series.length}'),
                const SizedBox(height: 16),
                CellMvChart(series: _series),
                const SizedBox(height: 16),
                TextField(
                  controller: _labelCtrl,
                  decoration: const InputDecoration(labelText: 'Label'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton(onPressed: _save, child: const Text('Save')),
                    if (_cell!.retiredDate == null)
                      OutlinedButton(
                        onPressed: _retire,
                        child: const Text('Retire'),
                      ),
                    TextButton(
                      onPressed: _deleteIfUnused,
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
