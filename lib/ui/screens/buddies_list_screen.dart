import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/db/dive_annotations_dao.dart';
import '../notifiers/buddies_notifier.dart';

/// The "Buddies list" (issue #15). Buddies are the distinct names across
/// every dive annotation's `buddies_json`, so this screen edits them as a
/// bulk operation: renaming a buddy rewrites every dive that names them
/// (and merges when the target name already exists), deleting removes them
/// from every dive without touching the dives themselves.
class BuddiesListScreen extends StatefulWidget {
  final DiveAnnotationsDao dao;

  const BuddiesListScreen({super.key, required this.dao});

  @override
  State<BuddiesListScreen> createState() => _BuddiesListScreenState();
}

class _BuddiesListScreenState extends State<BuddiesListScreen> {
  static final _dateFmt = DateFormat('yyyy-MM-dd');

  late final BuddiesNotifier _n;

  @override
  void initState() {
    super.initState();
    _n = BuddiesNotifier(widget.dao);
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

  String _formatDate(int unixSeconds) => _dateFmt
      .format(DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buddies')),
      body: _n.buddies.isEmpty ? _emptyState() : _list(),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.people_outline, size: 48),
            SizedBox(height: 16),
            Text(
              'No buddies recorded yet.\n'
              'Add buddies to your dives and they\'ll show up here.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _list() {
    return ListView.builder(
      itemCount: _n.buddies.length,
      itemBuilder: (context, i) {
        final b = _n.buddies[i];
        final dives = b.diveCount == 1 ? '1 dive' : '${b.diveCount} dives';
        final first = _formatDate(b.firstDiveTime);
        final last = _formatDate(b.lastDiveTime);
        final range = first == last ? first : '$first → $last';
        return ListTile(
          title: Text(b.name),
          subtitle: Text('$dives · $range'),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'rename') {
                _promptRename(b);
              } else if (value == 'delete') {
                _promptDelete(b);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        );
      },
    );
  }

  Future<void> _promptRename(BuddyStat b) async {
    final controller = TextEditingController(text: b.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Rename buddy'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (newName == null || newName.isEmpty || newName == b.name) return;

    // If the target already exists, the rename merges into it.
    final mergesInto =
        _n.buddies.any((other) => other.name != b.name && other.name == newName);

    await _n.rename(b.name, newName);
    if (!mounted) return;
    if (mergesInto) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Merged into $newName')),
      );
    }
  }

  Future<void> _promptDelete(BuddyStat b) async {
    final dives = b.diveCount == 1 ? '1 dive' : '${b.diveCount} dives';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Remove buddy'),
          content: Text(
            'Remove ${b.name} from all $dives? '
            "This doesn't delete the dives.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await _n.remove(b.name);
  }
}
