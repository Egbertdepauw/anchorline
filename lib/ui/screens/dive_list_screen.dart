import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../../data/db/dive_annotations_dao.dart';
import '../../data/db/dive_dao.dart';
import '../../data/db/equipment_dao.dart';
import '../notifiers/dive_list_notifier.dart';
import '../notifiers/settings_notifier.dart';
import '../util/dive_mode_color.dart';
import '../util/dive_search.dart';
import '../util/format.dart';
import '../widgets/dive_filter_sheet.dart';
import '../widgets/dive_tile.dart';
import 'dive_detail_screen.dart';

class DiveListScreen extends StatefulWidget {
  final DiveListNotifier notifier;
  final DiveDao diveDao;
  final DiveAnnotationsDao annotationsDao;
  final EquipmentDao equipmentDao;
  final SettingsNotifier settingsNotifier;

  const DiveListScreen({
    super.key,
    required this.notifier,
    required this.diveDao,
    required this.annotationsDao,
    required this.equipmentDao,
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
    return notifier.dives.where((d) {
      final ann = notifier.annotationsByDiveId[d.id];
      if (hasQuery && !diveMatchesQuery(d, ann, _query)) return false;
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

  Map<String, List<Dive>> _groupByMonth(List<Dive> dives) {
    final groups = <String, List<Dive>>{};
    for (final dive in dives) {
      final key = formatMonthYear(dive.startTime);
      groups.putIfAbsent(key, () => []).add(dive);
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
    final groups = _groupByMonth(filtered);

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
                              final dive = entry.value[index];
                              return _DiveTileWithSparkline(
                                dive: dive,
                                notifier: notifier,
                                diveDao: widget.diveDao,
                                annotationsDao: widget.annotationsDao,
                                equipmentDao: widget.equipmentDao,
                                settingsNotifier: widget.settingsNotifier,
                              );
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
  final DiveListNotifier notifier;
  final DiveDao diveDao;
  final DiveAnnotationsDao annotationsDao;
  final EquipmentDao equipmentDao;
  final SettingsNotifier settingsNotifier;

  const _DiveTileWithSparkline({
    required this.dive,
    required this.notifier,
    required this.diveDao,
    required this.annotationsDao,
    required this.equipmentDao,
    required this.settingsNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: notifier.getSparklineData(dive.id),
      builder: (context, snapshot) {
        return DiveTile(
          dive: dive,
          sparklineData: snapshot.data,
          annotation: notifier.annotationsByDiveId[dive.id],
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DiveDetailScreen(
                dive: dive,
                dao: diveDao,
                annotationsDao: annotationsDao,
                equipmentDao: equipmentDao,
                settingsNotifier: settingsNotifier,
              ),
            ));
            if (!context.mounted) return;
            await notifier.loadDives();
          },
        );
      },
    );
  }
}
