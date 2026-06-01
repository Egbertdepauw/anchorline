import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../../data/db/dive_annotations_dao.dart';
import '../../data/db/dive_attachments_dao.dart';
import '../../data/db/dive_dao.dart';
import '../../data/db/equipment_dao.dart';
import '../../analysis/merge/merged_sample_builder.dart';
import '../../sync/attachments/attachment_downloader.dart';
import '../../sync/attachments/attachment_uploader.dart';
import '../models/dive_list_item.dart';
import '../notifiers/dive_list_notifier.dart';
import '../notifiers/settings_notifier.dart';
import '../util/dive_mode_color.dart';
import '../util/dive_search.dart';
import '../util/format.dart';
import '../widgets/dive_filter_sheet.dart';
import '../widgets/dive_tile.dart';
import 'dive_detail_pager.dart';
import 'dive_detail_screen.dart';

class DiveListScreen extends StatefulWidget {
  final DiveListNotifier notifier;
  final DiveDao diveDao;
  final DiveAnnotationsDao annotationsDao;
  final EquipmentDao equipmentDao;
  // Optional attachments plumbing — when any is null the dive detail
  // pager hides the attachments section. Tests that don't traverse to
  // the detail screen omit them. Production wires all three from
  // [AppShell].
  final DiveAttachmentsDao? attachmentsDao;
  final AttachmentUploader? attachmentUploader;
  final AttachmentDownloader? attachmentDownloader;
  final SettingsNotifier settingsNotifier;

  const DiveListScreen({
    super.key,
    required this.notifier,
    required this.diveDao,
    required this.annotationsDao,
    required this.equipmentDao,
    this.attachmentsDao,
    this.attachmentUploader,
    this.attachmentDownloader,
    required this.settingsNotifier,
  });

  @override
  State<DiveListScreen> createState() => _DiveListScreenState();
}

class _DiveListScreenState extends State<DiveListScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  Timer? _debounce;
  DiveFilterSelection _filters = const DiveFilterSelection();

  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_onChanged);
    widget.notifier.loadDives();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    widget.notifier.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() => _query = value);
    });
  }

  List<Dive> get _filteredDives {
    final notifier = widget.notifier;
    final hasQuery = _query.trim().isNotEmpty;
    final hasFilters = !_filters.isEmpty;
    if (!hasQuery && !hasFilters) return notifier.dives;
    final seq = notifier.sequenceByDiveId;
    return notifier.dives.where((d) {
      final ann = notifier.annotationsByDiveId[d.id];
      if (hasQuery &&
          !diveMatchesQuery(d, ann, _query, sequenceNumber: seq[d.id])) {
        return false;
      }
      if (hasFilters &&
          !diveMatchesFilters(d, ann,
              mode: _filters.mode,
              sites: _filters.sites,
              buddies: _filters.buddies,
              tags: _filters.tags)) {
        return false;
      }
      return true;
    }).toList();
  }

  DiveFilterFacets _buildFacets() {
    final notifier = widget.notifier;
    final modes = distinctModesIn(notifier.dives.map((d) => d.diveMode));
    final sites = <String>{};
    final buddies = <String>{};
    final tags = <String>{};
    for (final d in notifier.dives) {
      final ann = notifier.annotationsByDiveId[d.id];
      if (ann == null) continue;
      final s = ann.siteName;
      if (s != null && s.trim().isNotEmpty) sites.add(s);
      buddies.addAll(ann.buddies.where((b) => b.trim().isNotEmpty));
      tags.addAll(ann.tags.where((t) => t.trim().isNotEmpty));
    }
    final siteList = sites.toList()..sort();
    final buddyList = buddies.toList()..sort();
    final tagList = tags.toList()..sort();
    return DiveFilterFacets(
      modes: modes, sites: siteList, buddies: buddyList, tags: tagList,
    );
  }

  Future<void> _openFilterSheet() async {
    final result = await showDiveFilterSheet(
      context,
      initial: _filters,
      facets: _buildFacets(),
    );
    if (result != null) {
      setState(() => _filters = result);
    }
  }

  void _removeMode() => setState(() => _filters = _filters.copyWith(clearMode: true));
  void _removeSite(String v) {
    final next = {..._filters.sites}..remove(v);
    setState(() => _filters = _filters.copyWith(sites: next));
  }
  void _removeBuddy(String v) {
    final next = {..._filters.buddies}..remove(v);
    setState(() => _filters = _filters.copyWith(buddies: next));
  }
  void _removeTag(String v) {
    final next = {..._filters.tags}..remove(v);
    setState(() => _filters = _filters.copyWith(tags: next));
  }

  /// Representative start time (epoch seconds) used to month-group and
  /// position a list item. A merged group sits at its latest member's start,
  /// so it lands naturally among the start-DESC singles.
  int _itemStartTime(DiveListItem item) => switch (item) {
        SingleDive(:final dive) => dive.startTime,
        MergedGroupItem(:final group) => group.latest.startTime,
      };

  Map<String, List<DiveListItem>> _groupByMonth(List<DiveListItem> items) {
    final groups = <String, List<DiveListItem>>{};
    for (final item in items) {
      final key = formatMonthYear(_itemStartTime(item));
      groups.putIfAbsent(key, () => []).add(item);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final notifier = widget.notifier;

    if (notifier.loading && notifier.dives.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (notifier.dives.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.scuba_diving,
                size: 48,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('No dives yet',
                style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5))),
          ],
        ),
      );
    }

    final filtered = _filteredDives;
    final items = buildListItems(filtered, notifier.links);
    final groups = _groupByMonth(items);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: _onQueryChanged,
                  decoration: InputDecoration(
                    hintText: 'Search dives',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              _debounce?.cancel();
                              setState(() => _query = '');
                            },
                          ),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                icon: const Icon(Icons.tune),
                tooltip: 'Filters',
                onPressed: _openFilterSheet,
              ),
            ],
          ),
        ),
        if (!_filters.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Wrap(
              spacing: 6, runSpacing: 4,
              children: [
                if (_filters.mode != null)
                  InputChip(
                    label: Text('Mode: ${diveModeLabel(_filters.mode!)}'),
                    onDeleted: _removeMode,
                  ),
                for (final s in _filters.sites)
                  InputChip(
                    label: Text('Site: $s'),
                    onDeleted: () => _removeSite(s),
                  ),
                for (final b in _filters.buddies)
                  InputChip(
                    label: Text('Buddy: $b'),
                    onDeleted: () => _removeBuddy(b),
                  ),
                for (final t in _filters.tags)
                  InputChip(
                    label: Text('Tag: $t'),
                    onDeleted: () => _removeTag(t),
                  ),
              ],
            ),
          ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No dives match.'))
              : RefreshIndicator(
                  onRefresh: notifier.loadDives,
                  child: CustomScrollView(
                    slivers: [
                      for (final entry in groups.entries) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                            child: Text(
                              entry.key,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ),
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final item = entry.value[index];
                              return switch (item) {
                                SingleDive(:final dive) =>
                                  _DiveTileWithSparkline(
                                    dive: dive,
                                    orderedDives: filtered,
                                    notifier: notifier,
                                    diveDao: widget.diveDao,
                                    annotationsDao: widget.annotationsDao,
                                    equipmentDao: widget.equipmentDao,
                                    attachmentsDao: widget.attachmentsDao,
                                    attachmentUploader:
                                        widget.attachmentUploader,
                                    attachmentDownloader:
                                        widget.attachmentDownloader,
                                    settingsNotifier: widget.settingsNotifier,
                                  ),
                                MergedGroupItem(:final group) =>
                                  _MergedGroupTile(
                                    group: group,
                                    notifier: notifier,
                                    diveDao: widget.diveDao,
                                    annotationsDao: widget.annotationsDao,
                                    equipmentDao: widget.equipmentDao,
                                    settingsNotifier: widget.settingsNotifier,
                                  ),
                              };
                            },
                            childCount: entry.value.length,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _DiveTileWithSparkline extends StatelessWidget {
  final Dive dive;

  /// The flat, ordered list of dives currently visible in the list (post
  /// filter + post group-flatten). Threaded through so a tap can hand the
  /// whole list to [DiveDetailPager], which lets the user swipe through
  /// neighbours from the detail screen.
  final List<Dive> orderedDives;

  final DiveListNotifier notifier;
  final DiveDao diveDao;
  final DiveAnnotationsDao annotationsDao;
  final EquipmentDao equipmentDao;
  final DiveAttachmentsDao? attachmentsDao;
  final AttachmentUploader? attachmentUploader;
  final AttachmentDownloader? attachmentDownloader;
  final SettingsNotifier settingsNotifier;

  const _DiveTileWithSparkline({
    required this.dive,
    required this.orderedDives,
    required this.notifier,
    required this.diveDao,
    required this.annotationsDao,
    required this.equipmentDao,
    required this.attachmentsDao,
    required this.attachmentUploader,
    required this.attachmentDownloader,
    required this.settingsNotifier,
  });

  @override
  Widget build(BuildContext context) {
    final selecting = notifier.selectionMode;
    final selected = notifier.isSelected(dive.id);
    return FutureBuilder(
      future: notifier.getSparklineData(dive.id),
      builder: (context, snapshot) {
        final ann = notifier.annotationsByDiveId[dive.id];
        final sequenceMap = notifier.sequenceByDiveId;
        final tile = DiveTile(
          dive: dive,
          sparklineData: snapshot.data,
          annotation: ann,
          sequenceNumber: sequenceMap[dive.id],
          onTap: () async {
            final initialIndex =
                orderedDives.indexWhere((d) => d.id == dive.id);
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DiveDetailPager(
                dives: orderedDives,
                initialIndex: initialIndex < 0 ? 0 : initialIndex,
                sequenceByDiveId: sequenceMap,
                diveDao: diveDao,
                annotationsDao: annotationsDao,
                equipmentDao: equipmentDao,
                attachmentsDao: attachmentsDao,
                attachmentUploader: attachmentUploader,
                attachmentDownloader: attachmentDownloader,
                settingsNotifier: settingsNotifier,
              ),
            ));
            if (!context.mounted) return;
            await notifier.loadDives();
          },
        );

        // Selection mode: a leading checkbox + whole-row tap toggles
        // selection. Swipe-to-delete is suppressed to avoid gesture
        // conflicts and accidental deletes while multi-selecting.
        if (selecting) {
          return Material(
            color: selected
                ? Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.08)
                : null,
            child: InkWell(
              onTap: () => notifier.toggleSelected(dive.id),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  IgnorePointer(
                    child: Checkbox(value: selected, onChanged: (_) {}),
                  ),
                  Expanded(child: IgnorePointer(child: tile)),
                ],
              ),
            ),
          );
        }

        return GestureDetector(
          onLongPress: () => notifier.enterSelectionMode(dive.id),
          child: Dismissible(
          key: ValueKey(dive.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            color: Colors.red.shade700,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          confirmDismiss: (_) async {
            return await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete dive?'),
                    content: Text(
                        'Hides #${sequenceMap[dive.id] ?? dive.dcDiveNumber} from the list. You can undo from the SnackBar that appears.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                ) ??
                false;
          },
          onDismissed: (_) async {
            final messenger = ScaffoldMessenger.of(context);
            await notifier.softDeleteDive(dive.id);
            if (!context.mounted) return;
            messenger.showSnackBar(SnackBar(
              content: Text(
                  'Dive #${sequenceMap[dive.id] ?? dive.dcDiveNumber} deleted'),
              action: SnackBarAction(
                label: 'UNDO',
                onPressed: () => notifier.restoreDive(dive.id),
              ),
              duration: const Duration(seconds: 6),
            ));
          },
            child: tile,
          ),
        );
      },
    );
  }
}

class _MergedGroupTile extends StatelessWidget {
  final MergeGroup group;
  final DiveListNotifier notifier;
  final DiveDao diveDao;
  final DiveAnnotationsDao annotationsDao;
  final EquipmentDao equipmentDao;
  final SettingsNotifier settingsNotifier;

  const _MergedGroupTile({
    required this.group,
    required this.notifier,
    required this.diveDao,
    required this.annotationsDao,
    required this.equipmentDao,
    required this.settingsNotifier,
  });

  String _mergeLine() {
    final gaps = group.surfaceGapsSeconds;
    final si = gaps.length == 1
        ? 'SI ${formatDuration(gaps.first)}'
        : '${gaps.length} surface intervals';
    return '${group.members.length} dives · $si';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A summary dive that reuses the normal DiveTile layout: earliest member's
    // identity (mode, site, date, CCRLog sequence number) with the combined
    // max depth + total in-water time substituted in.
    final summaryDive = group.earliest.copyWith(
      maxDepthMm: group.maxDepthMm,
      durationSeconds: group.totalInWaterSeconds,
    );
    final seq = notifier.sequenceByDiveId[group.earliest.id];
    final ann = notifier.annotationsByDiveId[group.earliest.id];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FutureBuilder(
          future: notifier
              .getMergedSparklineData(group.members.map((m) => m.id).toList()),
          builder: (context, snapshot) => DiveTile(
            dive: summaryDive,
            sparklineData: snapshot.data,
            annotation: ann,
            sequenceNumber: seq,
            onTap: () => _openMerged(context),
          ),
        ),
        // Extra line marking this as a merge: chain icon + dive count + SI.
        InkWell(
          onTap: () => _openMerged(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
            child: Row(
              children: [
                Icon(Icons.link, size: 14, color: scheme.outlineVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _mergeLine(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.outlineVariant,
                        ),
                  ),
                ),
                SizedBox(
                  height: 28,
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    tooltip: 'Merge options',
                    icon: Icon(Icons.more_vert,
                        size: 18, color: scheme.outlineVariant),
                    onSelected: (v) {
                      if (v == 'unmerge') notifier.unmergeGroup(group.groupId);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'unmerge', child: Text('Unmerge')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openMerged(BuildContext context) async {
    final navigator = Navigator.of(context);
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final members = <MergeMember>[];
    for (final dv in group.members) {
      final samples = await diveDao.getSamples(dv.id);
      if (samples == null) {
        rootNavigator.pop(); // dismiss loader
        messenger.showSnackBar(const SnackBar(
            content: Text('Samples not available yet — try again later.')));
        return;
      }
      members.add((dive: dv, samples: samples));
    }
    final merged = buildMergedDive(mergedId: group.groupId, members: members);
    rootNavigator.pop(); // dismiss loader
    // The synthetic dive's id is the merge-group id, not a real dive, so
    // annotation editing is suppressed (saving would orphan a row). Sections
    // keyed on the dive (bailout carry, mapped cylinders, active cells) read
    // as-if the first member — empty/first-dive values — acceptable for the
    // merged profile view in v1.
    await navigator.push(MaterialPageRoute(
      builder: (_) => DiveDetailScreen(
        dive: merged.dive,
        preloadedSamples: merged.samples,
        dao: diveDao,
        annotationsDao: annotationsDao,
        equipmentDao: equipmentDao,
        settingsNotifier: settingsNotifier,
        annotationsEditable: false,
        // Show the CCRLog sequence number of the earliest member (e.g. #716),
        // not the synthetic dive's raw dcDiveNumber.
        sequenceNumber: notifier.sequenceByDiveId[group.earliest.id],
      ),
    ));
    await notifier.loadDives();
  }
}
