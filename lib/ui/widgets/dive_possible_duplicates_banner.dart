/// Banner on the dive detail screen for a dive that was stored with a flag:
/// several stored dives look like the same dive (see
/// `ImportOutcome.insertedFlagged`). It links to each of them. There is no
/// dismiss in phase 1; folding duplicate pairs is a follow-up.
library;

import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../../data/db/dive_dao.dart';
import '../theme/tokens.dart';
import '../util/format.dart';

class DivePossibleDuplicatesBanner extends StatefulWidget {
  /// The dive shown. For a merged dive ([merged]) this is the merge group's
  /// id, and every member of the group is checked.
  final String diveId;
  final bool merged;
  final DiveDao dao;

  /// Opens a candidate dive.
  final void Function(Dive dive) onOpen;

  const DivePossibleDuplicatesBanner({
    super.key,
    required this.diveId,
    this.merged = false,
    required this.dao,
    required this.onOpen,
  });

  @override
  State<DivePossibleDuplicatesBanner> createState() =>
      _DivePossibleDuplicatesBannerState();
}

class _DivePossibleDuplicatesBannerState
    extends State<DivePossibleDuplicatesBanner> {
  List<Dive> _candidates = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DivePossibleDuplicatesBanner old) {
    super.didUpdateWidget(old);
    if (old.diveId != widget.diveId || old.merged != widget.merged) _load();
  }

  Future<void> _load() async {
    final id = widget.diveId;
    final found = <Dive>[];
    try {
      final members =
          widget.merged ? await widget.dao.mergeGroupMemberIds(id) : [id];
      final seen = {...members};
      for (final m in members) {
        for (final c in await widget.dao.matchCandidates(m)) {
          if (!seen.add(c)) continue;
          final dive = await widget.dao.getDive(c);
          // A candidate that has since been deleted is no longer a duplicate
          // the diver can open.
          if (dive != null && dive.deletedAt == null) found.add(dive);
        }
      }
    } catch (_) {
      // The banner is a hint; without it the screen works as before.
      return;
    }
    if (!mounted || id != widget.diveId) return;
    setState(() => _candidates = found);
  }

  @override
  Widget build(BuildContext context) {
    if (_candidates.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final palette = context.palette;
    final n = _candidates.length;
    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceCard,
        border: Border(left: BorderSide(color: palette.accentPrimary, width: 3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline,
                  size: 18, color: palette.accentPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This dive may be the same as $n other '
                  '${n == 1 ? 'dive' : 'dives'} in your log.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: palette.textPrimary),
                ),
              ),
            ],
          ),
          for (final d in _candidates)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: palette.accentPrimary),
                onPressed: () => widget.onOpen(d),
                child: Text(formatDateTime(d.startTime)),
              ),
            ),
        ],
      ),
    );
  }
}
