import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/db/dive_annotations_dao.dart';
import '../notifiers/sites_notifier.dart';

/// The "Dive sites list" body (issue #16). Sites are the distinct
/// `site_name` values across every dive annotation, so this view edits them
/// as a bulk operation: renaming a site rewrites every dive that names it
/// (and merges when the target name already exists), deleting clears the site
/// (name + coords) from every dive without touching the dives themselves.
///
/// This is a reusable body widget (NOT a full Scaffold) so it can be embedded
/// inside the map screen's map/list toggle. It owns its own [SitesNotifier].
class SitesListView extends StatefulWidget {
  final DiveAnnotationsDao dao;

  const SitesListView({super.key, required this.dao});

  @override
  State<SitesListView> createState() => _SitesListViewState();
}

class _SitesListViewState extends State<SitesListView> {
  static final _dateFmt = DateFormat('yyyy-MM-dd');

  late final SitesNotifier _n;

  @override
  void initState() {
    super.initState();
    _n = SitesNotifier(widget.dao);
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
    return _n.sites.isEmpty ? _emptyState() : _list();
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.place_outlined, size: 48),
            SizedBox(height: 16),
            Text(
              'No dive sites recorded yet.\n'
              'Add a site to your dives and they\'ll show up here.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _list() {
    return ListView.builder(
      itemCount: _n.sites.length,
      itemBuilder: (context, i) {
        final s = _n.sites[i];
        final dives = s.diveCount == 1 ? '1 dive' : '${s.diveCount} dives';
        final first = _formatDate(s.firstDiveTime);
        final last = _formatDate(s.lastDiveTime);
        final range = first == last ? first : '$first → $last';
        return ListTile(
          title: Text(s.name),
          subtitle: Text('$dives · $range'),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'rename') {
                _promptRename(s);
              } else if (value == 'delete') {
                _promptDelete(s);
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

  Future<void> _promptRename(SiteStat s) async {
    final controller = TextEditingController(text: s.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Rename site'),
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
    if (newName == null || newName.isEmpty || newName == s.name) return;

    // If the target already exists, the rename merges into it.
    final mergesInto =
        _n.sites.any((other) => other.name != s.name && other.name == newName);

    await _n.rename(s.name, newName);
    if (!mounted) return;
    if (mergesInto) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Merged into $newName')),
      );
    }
  }

  Future<void> _promptDelete(SiteStat s) async {
    final dives = s.diveCount == 1 ? '1 dive' : '${s.diveCount} dives';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Remove site'),
          content: Text(
            'Remove site ${s.name} from all $dives? '
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
    await _n.remove(s.name);
  }
}
