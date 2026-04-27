import 'package:flutter/material.dart';

import '../../../data/db/database.dart';
import '../../../data/db/equipment_dao.dart';
import '../../widgets/cell_mv_chart.dart';

class CellDetailScreen extends StatefulWidget {
  final EquipmentDao dao;
  final String? id; // null = create-new draft

  const CellDetailScreen({super.key, required this.dao, this.id});

  @override
  State<CellDetailScreen> createState() => _CellDetailScreenState();
}

class _CellDetailScreenState extends State<CellDetailScreen> {
  OxygenCell? _cell;
  List<({DateTime date, double mv, String diveId})> _series = const [];
  final _labelCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool get _isDraft => widget.id == null;

  @override
  void initState() {
    super.initState();
    if (!_isDraft) _load();
  }

  Future<void> _load() async {
    final cell = await widget.dao.getCell(widget.id!);
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
    final label = _labelCtrl.text.trim();
    final notes = _notesCtrl.text.trim();
    if (_isDraft) {
      final newId = await widget.dao.addCell(
        slot: 1,
        label: label.isEmpty ? null : label,
        notes: notes.isEmpty ? null : notes,
      );
      if (!mounted) return;
      Navigator.of(context).pop(newId);
    } else {
      await widget.dao.updateCell(
        _cell!.id,
        label: label,
        notes: notes,
      );
      await _load();
    }
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
      body: (!_isDraft && _cell == null)
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Slot ${_cell?.slot ?? 1}',
                    style: Theme.of(context).textTheme.titleMedium),
                if (_cell?.installedDate != null)
                  Text('Installed: '
                      '${DateTime.fromMillisecondsSinceEpoch(_cell!.installedDate!).toLocal().toString().split(' ').first}'),
                if (_cell?.retiredDate != null)
                  Text('Retired: '
                      '${DateTime.fromMillisecondsSinceEpoch(_cell!.retiredDate!).toLocal().toString().split(' ').first}'),
                Text('Dives with mV data: ${_series.length}'),
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
                    if (!_isDraft && _cell?.retiredDate == null)
                      OutlinedButton(
                        onPressed: _retire,
                        child: const Text('Retire'),
                      ),
                    if (!_isDraft)
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
