import 'package:flutter/material.dart';

import '../../../data/db/database.dart';
import '../../../data/db/equipment_dao.dart';

class ScrubberSessionDetailScreen extends StatefulWidget {
  final EquipmentDao dao;
  final String id;

  const ScrubberSessionDetailScreen({
    super.key,
    required this.dao,
    required this.id,
  });

  @override
  State<ScrubberSessionDetailScreen> createState() =>
      _ScrubberSessionDetailScreenState();
}

class _ScrubberSessionDetailScreenState
    extends State<ScrubberSessionDetailScreen> {
  ScrubberSession? _session;
  int _accumulated = 0;
  final _mediaCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await widget.dao.getScrubberSession(widget.id);
    if (s == null) return;
    final m = await widget.dao.accumulatedMinutesForSession(s.id);
    if (!mounted) return;
    setState(() {
      _session = s;
      _accumulated = m;
      _mediaCtrl.text = s.mediaType ?? '';
      _notesCtrl.text = s.notes ?? '';
    });
  }

  Future<void> _close() async {
    await widget.dao.closeScrubberSession(widget.id, endedAt: DateTime.now());
    await _load();
  }

  Future<void> _save() async {
    if (_session == null) return;
    await widget.dao.updateScrubberSession(
      widget.id,
      mediaType: _mediaCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
    );
    await _load();
  }

  Future<void> _delete() async {
    await widget.dao.deleteScrubberSession(widget.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _mediaCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scrubber Pack')),
      body: _session == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Started: ${_session!.startedDate == null ? '?' : DateTime.fromMillisecondsSinceEpoch(_session!.startedDate!).toLocal().toString().split(' ').first}'),
                Text('Accumulated: ${_accumulated ~/ 60}h ${_accumulated % 60}m'),
                const SizedBox(height: 16),
                TextField(
                  controller: _mediaCtrl,
                  decoration: const InputDecoration(labelText: 'Media type'),
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
                    if (_session!.totalMinutes == null)
                      OutlinedButton(
                        onPressed: _close,
                        child: const Text('Close'),
                      ),
                    TextButton(onPressed: _delete, child: const Text('Delete')),
                  ],
                ),
              ],
            ),
    );
  }
}
