/// Pure guardrail logic for merging dives. No I/O, no Flutter.
library;

import '../../data/db/database.dart';
import 'merge_constants.dart';

class MergeEligibility {
  final bool canMerge;
  final String? reason;
  const MergeEligibility._(this.canMerge, this.reason);
  factory MergeEligibility.ok() => const MergeEligibility._(true, null);
  factory MergeEligibility.no(String reason) =>
      MergeEligibility._(false, reason);
}

/// Surface interval between [prev] and [next], in seconds
/// (startTime/endTime are epoch seconds). Negative when dives overlap.
int surfaceGapSeconds(Dive prev, Dive next) => next.startTime - prev.endTime;

/// Validates whether [selected] can be merged, given the full [allDives]
/// list (needed for the adjacency check). [allDives] need not be sorted.
MergeEligibility validateMerge({
  required List<Dive> selected,
  required List<Dive> allDives,
}) {
  if (selected.length < 2) {
    return MergeEligibility.no('Select at least 2 dives to merge.');
  }

  final serial = selected.first.dcSerial;
  if (selected.any((dv) => dv.dcSerial != serial)) {
    return MergeEligibility.no('Dives must be from the same dive computer.');
  }

  final sorted = [...selected]
    ..sort((x, y) => x.startTime.compareTo(y.startTime));
  final selectedIds = sorted.map((dv) => dv.id).toSet();

  // Adjacency: no un-selected dive may start strictly between the first and
  // last selected start times.
  final firstStart = sorted.first.startTime;
  final lastStart = sorted.last.startTime;
  for (final dv in allDives) {
    if (selectedIds.contains(dv.id)) continue;
    if (dv.startTime > firstStart && dv.startTime < lastStart) {
      return MergeEligibility.no('Selected dives are not consecutive.');
    }
  }

  // Surface-interval checks on each consecutive pair.
  for (var i = 1; i < sorted.length; i++) {
    final gap = surfaceGapSeconds(sorted[i - 1], sorted[i]);
    if (gap < 0) {
      return MergeEligibility.no('Dives overlap in time.');
    }
    if (gap > kMergeMaxSurfaceGap.inSeconds) {
      return MergeEligibility.no(
          'Surface interval exceeds 1 h between two dives.');
    }
  }

  return MergeEligibility.ok();
}
