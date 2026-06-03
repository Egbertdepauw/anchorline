import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../../analysis/cell_health.dart';
import '../../../data/db/database.dart';
import '../../../data/db/dive_annotations_dao.dart';
import '../../../data/db/dive_dao.dart';
import '../../../data/db/equipment_dao.dart';
import '../../../data/models/equipment.dart' show SlotInUseException;
import '../../notifiers/settings_notifier.dart';
import '../../widgets/cell_health_strip.dart';
import '../../widgets/cell_mv_chart.dart';
import '../dive_detail_screen.dart';

class CellDetailScreen extends StatefulWidget {
  final EquipmentDao dao;
  final DiveDao diveDao;
  final DiveAnnotationsDao annotationsDao;
  final SettingsNotifier settingsNotifier;
  final String? id; // null = create-new draft

  const CellDetailScreen({
    super.key,
    required this.dao,
    required this.diveDao,
    required this.annotationsDao,
    required this.settingsNotifier,
    this.id,
  });

  @override
  State<CellDetailScreen> createState() => _CellDetailScreenState();
}

class _CellDetailScreenState extends State<CellDetailScreen> {
  OxygenCell? _cell;
  List<({DateTime date, double mv, String diveId})> _surface = const [];
  List<({DateTime date, double mv, String diveId})> _peak = const [];
  CellHealth? _health;
  final _labelCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime? _installedDate;
  int _slot = 1;

  bool get _isDraft => widget.id == null;

  @override
  void initState() {
    super.initState();
    if (_isDraft) {
      final now = DateTime.now();
      _installedDate = DateTime(now.year, now.month, now.day);
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final cell = await widget.dao.getCell(widget.id!);
    if (cell == null) return;
    final mv = await widget.dao.mvSeriesForCell(cell.id);
    final health = await widget.dao.evaluateHealthForCell(cell.id);
    if (!mounted) return;
    setState(() {
      _cell = cell;
      _surface = mv.surface;
      _peak = mv.peak;
      _health = health;
      _slot = cell.slot;
      _labelCtrl.text = cell.label ?? '';
      _notesCtrl.text = cell.notes ?? '';
      _installedDate = cell.installedDate == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(cell.installedDate!);
    });
  }

  Future<void> _pickInstalledDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _installedDate ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;
    setState(() {
      _installedDate = DateTime(picked.year, picked.month, picked.day);
    });
  }

  void _clearInstalledDate() {
    setState(() => _installedDate = null);
  }

  Future<void> _save() async {
    final label = _labelCtrl.text.trim();
    final notes = _notesCtrl.text.trim();
    try {
      if (_isDraft) {
        final newId = await widget.dao.addCell(
          slot: _slot,
          label: label.isEmpty ? null : label,
          installedDate: _installedDate,
          notes: notes.isEmpty ? null : notes,
        );
        if (!mounted) return;
        Navigator.of(context).pop(newId);
      } else {
        await widget.dao.updateCell(
          _cell!.id,
          slot: _slot != _cell!.slot ? _slot : null,
          label: label,
          installedDate: Value(_installedDate),
          notes: notes,
        );
        await _load();
      }
    } on SlotInUseException catch (e) {
      if (!mounted) return;
      final otherLabel = (e.otherLabel == null || e.otherLabel!.isEmpty)
          ? 'unlabeled cell'
          : e.otherLabel!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            "Slot ${e.slot} is already in use by '$otherLabel'. Retire that cell first."),
      ));
    }
  }

  Future<void> _retire() async {
    if (_cell == null) return;
    await widget.dao.retireCell(_cell!.id, retiredAt: DateTime.now());
    await _load();
  }

  Future<void> _openDive(String diveId) async {
    final dive = await widget.diveDao.getDive(diveId);
    if (dive == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DiveDetailScreen(
        dive: dive,
        dao: widget.diveDao,
        annotationsDao: widget.annotationsDao,
        equipmentDao: widget.dao,
        settingsNotifier: widget.settingsNotifier,
      ),
    ));
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

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cell'),
        actions: [
          if (!_isDraft && _cell?.retiredDate == null)
            IconButton(
              tooltip: 'Retire',
              icon: const Icon(Icons.archive_outlined),
              onPressed: _retire,
            ),
          IconButton(
            tooltip: 'Save',
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
          if (!_isDraft)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteIfUnused,
            ),
        ],
      ),
      body: (!_isDraft && _cell == null)
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Slot 4 has no per-sample mV trace — Petrel binary only carries 3 cells; longitudinal mV charts will be empty for slot 4 until additional data sources are wired in.
                DropdownButtonFormField<int>(
                  initialValue: _slot,
                  decoration: const InputDecoration(labelText: 'Slot'),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1')),
                    DropdownMenuItem(value: 2, child: Text('2')),
                    DropdownMenuItem(value: 3, child: Text('3')),
                    DropdownMenuItem(value: 4, child: Text('4')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _slot = v);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_installedDate == null
                      ? 'Installed: —'
                      : 'Installed: ${_fmtDate(_installedDate!)}'),
                  trailing: _installedDate == null
                      ? const Icon(Icons.calendar_today)
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.clear),
                          onPressed: _clearInstalledDate,
                        ),
                  onTap: _pickInstalledDate,
                ),
                if (_cell?.retiredDate != null)
                  Text('Retired: '
                      '${_fmtDate(DateTime.fromMillisecondsSinceEpoch(_cell!.retiredDate!))}'),
                Text('Dives with mV data: ${_peak.length}'),
                const SizedBox(height: 16),
                if (_health != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: CellHealthStrip(health: _health!, slot: _slot),
                  ),
                CellMvChart(
                  surfaceSeries: _surface,
                  peakSeries: _peak,
                  baselinePeakMv: _health?.baselinePeakMv,
                  onDiveTap: _openDive,
                ),
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
              ],
            ),
    );
  }
}
