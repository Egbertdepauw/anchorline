/// View model for the dive list: either a lone dive or a collapsed merge
/// group. [buildListItems] is pure and unit-tested.
library;

import 'dart:math' as math;

import '../../data/db/database.dart';
import '../../data/db/dive_merge_dao.dart';

/// A merge group's members, sorted by start time ascending (chronological).
class MergeGroup {
  final String groupId;
  final List<Dive> members;
  const MergeGroup({required this.groupId, required this.members});

  Dive get earliest => members.first;
  Dive get latest => members.last;

  int get totalInWaterSeconds =>
      members.fold(0, (s, dv) => s + dv.durationSeconds);

  int get maxDepthMm => members.map((dv) => dv.maxDepthMm).reduce(math.max);

  /// Surface intervals (seconds) between consecutive members.
  List<int> get surfaceGapsSeconds => [
        for (var i = 1; i < members.length; i++)
          members[i].startTime - members[i - 1].endTime,
      ];
}

sealed class DiveListItem {
  const DiveListItem();
}

class SingleDive extends DiveListItem {
  final Dive dive;
  const SingleDive(this.dive);
}

class MergedGroupItem extends DiveListItem {
  final MergeGroup group;
  const MergedGroupItem(this.group);
}

/// Collapses [dives] (expected start-DESC, as from getAllDives) and active
/// [links] into list items. A group needs >=2 present members to collapse;
/// otherwise its lone member renders as a normal single dive. The group is
/// emitted at the position of its first-encountered (latest) member.
List<DiveListItem> buildListItems(List<Dive> dives, List<MergeLink> links) {
  final groupOf = {for (final l in links) l.diveId: l.groupId};

  final membersByGroup = <String, List<Dive>>{};
  for (final dv in dives) {
    final g = groupOf[dv.id];
    if (g != null) {
      membersByGroup.putIfAbsent(g, () => []).add(dv);
    }
  }
  final validGroups = <String, MergeGroup>{};
  for (final e in membersByGroup.entries) {
    if (e.value.length >= 2) {
      final sorted = [...e.value]
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      validGroups[e.key] = MergeGroup(groupId: e.key, members: sorted);
    }
  }

  final items = <DiveListItem>[];
  final emitted = <String>{};
  for (final dv in dives) {
    final g = groupOf[dv.id];
    if (g != null && validGroups.containsKey(g)) {
      if (emitted.add(g)) {
        items.add(MergedGroupItem(validGroups[g]!));
      }
    } else {
      items.add(SingleDive(dv));
    }
  }
  return items;
}
