import 'package:flutter/material.dart';

import '../../../data/db/database.dart';
import '../../../data/db/equipment_dao.dart';

class DiveComputerDetailScreen extends StatefulWidget {
  final EquipmentDao dao;
  final String id;

  const DiveComputerDetailScreen({
    super.key,
    required this.dao,
    required this.id,
  });

  @override
  State<DiveComputerDetailScreen> createState() =>
      _DiveComputerDetailScreenState();
}

class _DiveComputerDetailScreenState extends State<DiveComputerDetailScreen> {
  DiveComputer? _dc;
  List<Dive> _recent = [];
  List<PressureMapping> _mappings = [];
  List<Cylinder> _cylinders = [];
  final _nicknameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (mounted) _loadMappings();
    });
  }

  Future<void> _load() async {
    final list = await widget.dao.listDiveComputers();
    final dc = list.where((d) => d.id == widget.id).firstOrNull;
    if (dc == null) return;
    final recent = await widget.dao.recentImportsForComputer(dc.serial);
    if (!mounted) return;
    setState(() {
      _dc = dc;
      _recent = recent;
      _nicknameCtrl.text = dc.nickname ?? '';
    });
  }

  Future<void> _saveNickname() async {
    if (_dc == null) return;
    final v = _nicknameCtrl.text.trim();
    await widget.dao.setComputerNickname(_dc!.id, v.isEmpty ? null : v);
    await _load();
  }

  Future<void> _loadMappings() async {
    if (_dc == null) return;
    final mappings = await widget.dao.listPressureMappings(_dc!.id);
    final cylinders = await widget.dao.listCylinders();
    if (!mounted) return;
    setState(() {
      _mappings = mappings;
      _cylinders = cylinders;
    });
  }

  Future<void> _setMapping(int channel, String? cylinderId) async {
    if (_dc == null) return;
    await widget.dao.setPressureMapping(
      diveComputerId: _dc!.id,
      channelIndex: channel,
      cylinderId: cylinderId,
    );
    await _loadMappings();
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dive Computer')),
      body: _dc == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Serial: ${_dc!.serial.toRadixString(16).toUpperCase()}'),
                Text('Model: ${_dc!.model}'),
                Text('Firmware: ${_dc!.firmwareVersion ?? '?'}'),
                const SizedBox(height: 16),
                TextField(
                  controller: _nicknameCtrl,
                  decoration: const InputDecoration(labelText: 'Nickname'),
                  onSubmitted: (_) => _saveNickname(),
                ),
                ElevatedButton(
                  onPressed: _saveNickname,
                  child: const Text('Save nickname'),
                ),
                const SizedBox(height: 24),
                const Text('Recent imports',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                if (_recent.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No imports yet'),
                  ),
                for (final d in _recent)
                  ListTile(
                    dense: true,
                    title: Text('Dive #${d.dcDiveNumber}'),
                    // Real Dives schema field: startTime (NOT startTimeUtc).
                    // startTime is Unix seconds UTC; multiply by 1000 for ms.
                    subtitle: Text(DateTime.fromMillisecondsSinceEpoch(
                            d.startTime * 1000)
                        .toLocal()
                        .toString()),
                  ),
                const SizedBox(height: 24),
                const Text('Pressure mapping',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                if (_mappings.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No pressure channels mapped yet. Add a channel manually for '
                      'channel 0–3 if your device logs pressure.',
                    ),
                  ),
                for (final m in _mappings)
                  ListTile(
                    dense: true,
                    title: Text('Channel ${m.channelIndex}'),
                    trailing: DropdownButton<String?>(
                      value: m.cylinderId,
                      hint: const Text('unmapped'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('unmapped'),
                        ),
                        for (final c in _cylinders)
                          DropdownMenuItem<String?>(
                            value: c.id,
                            child: Text('${c.label} (${c.role})'),
                          ),
                      ],
                      onChanged: (v) => _setMapping(m.channelIndex, v),
                    ),
                  ),
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add channel'),
                  onPressed: () async {
                    final used = _mappings.map((m) => m.channelIndex).toSet();
                    var next = 0;
                    while (used.contains(next)) {
                      next++;
                    }
                    await _setMapping(next, null);
                  },
                ),
              ],
            ),
    );
  }
}
