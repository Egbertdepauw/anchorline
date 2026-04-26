import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../../data/db/dive_dao.dart';
import '../notifiers/dive_list_notifier.dart';
import '../widgets/dive_tile.dart';
import 'dive_detail_screen.dart';

class DiveListScreen extends StatefulWidget {
  final DiveListNotifier notifier;
  final DiveDao diveDao;

  const DiveListScreen(
      {super.key, required this.notifier, required this.diveDao});

  @override
  State<DiveListScreen> createState() => _DiveListScreenState();
}

class _DiveListScreenState extends State<DiveListScreen> {
  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_onChanged);
    widget.notifier.loadDives();
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

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

    final groups = notifier.groupedByMonth;

    return RefreshIndicator(
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
                      diveDao: widget.diveDao);
                },
                childCount: entry.value.length,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DiveTileWithSparkline extends StatelessWidget {
  final Dive dive;
  final DiveListNotifier notifier;
  final DiveDao diveDao;

  const _DiveTileWithSparkline(
      {required this.dive, required this.notifier, required this.diveDao});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: notifier.getSparklineData(dive.id),
      builder: (context, snapshot) {
        return DiveTile(
          dive: dive,
          sparklineData: snapshot.data,
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DiveDetailScreen(dive: dive, dao: diveDao),
            ));
          },
        );
      },
    );
  }
}
