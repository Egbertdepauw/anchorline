import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../../data/db/dive_annotations_dao.dart';
import '../../data/db/dive_dao.dart';
import '../../data/db/equipment_dao.dart';
import '../notifiers/dive_list_notifier.dart';
import '../notifiers/settings_notifier.dart';
import '../util/dive_search.dart';
import '../util/format.dart';
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
    if (_query.trim().isEmpty) return notifier.dives;
    return notifier.dives
        .where((d) => diveMatchesQuery(
            d, notifier.annotationsByDiveId[d.id], _query))
        .toList();
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
