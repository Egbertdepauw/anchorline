import 'package:flutter/material.dart';

import '../../../data/db/database.dart';
import '../../../data/db/equipment_dao.dart';
import '../../notifiers/equipment_notifiers.dart';
import 'scrubber_session_detail_screen.dart';

class ScrubberSessionsListScreen extends StatefulWidget {
  final EquipmentDao dao;

  const ScrubberSessionsListScreen({super.key, required this.dao});

  @override
  State<ScrubberSessionsListScreen> createState() =>
      _ScrubberSessionsListScreenState();
}

class _ScrubberSessionsListScreenState
    extends State<ScrubberSessionsListScreen> {
  late final ScrubberSessionsNotifier _n;

  @override
  void initState() {
    super.initState();
    _n = ScrubberSessionsNotifier(widget.dao);
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
      appBar: AppBar(title: const Text('Scrubber Sessions')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New pack'),
        onPressed: () async {
          await _n.addPack(startedDate: DateTime.now());
        },
      ),
      body: _n.sessions.isEmpty
          ? const Center(child: Text('No sessions yet'))
          : ListView.builder(
              itemCount: _n.sessions.length,
              itemBuilder: (_, i) {
                final s = _n.sessions[i];
                final active = s.totalMinutes == null;
                return ListTile(
                  title: Text(_title(s)),
                  subtitle: Text(_subtitle(s)),
                  trailing: active
                      ? const Chip(label: Text('Active'))
                      : null,
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ScrubberSessionDetailScreen(
                        dao: widget.dao,
                        id: s.id,
                      ),
                    ));
                    await _n.load();
                  },
                );
              },
            ),
    );
  }

  String _title(ScrubberSession s) {
    final d = s.startedDate == null
        ? '?'
        : DateTime.fromMillisecondsSinceEpoch(s.startedDate!)
            .toLocal()
            .toString()
            .split(' ')
            .first;
    return 'Pack started $d';
  }

  String _subtitle(ScrubberSession s) {
    final m = s.totalMinutes ?? 0;
    final h = m ~/ 60;
    final r = m % 60;
    return '${h}h ${r}m used${s.mediaType == null ? '' : ' · ${s.mediaType}'}';
  }
}
