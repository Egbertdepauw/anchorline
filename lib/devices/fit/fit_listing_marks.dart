/// Marks the dives of a FIT import the diver already has.
library;

import '../../data/db/dive_dao.dart';
import '../dive_download_source.dart';
import 'fit_file_source.dart';

/// The note on a dive the diver already has.
const String kFitAlreadyStoredFlag = 'Already in Anchorline';

/// [listed] as new listings: a dive the diver already has gets
/// [kFitAlreadyStoredFlag], one that overlaps another computer's dive gets
/// "Overlaps your <label> dive"; both start unticked.
Future<List<DiveListing>> markFitListings(
    DiveDao dao, FitDownloadSource source, List<DiveListing> listed) async {
  final stored =
      await dao.existingDiveIdsAmong([for (final l in listed) l.diveId]);

  // What alreadyDownloadedAmong hides is decided per watch.
  final byWatch = <String, List<DiveListing>>{};
  final watchOf = <String, ({String vendor, int serial})>{};
  for (final l in listed) {
    final w = source.watchOf(l.diveId);
    if (w == null) continue;
    watchOf[l.diveId] = w;
    byWatch.putIfAbsent('${w.vendor}:${w.serial}', () => []).add(l);
  }
  final downloaded = <String>{};
  for (final group in byWatch.values) {
    final w = watchOf[group.first.diveId]!;
    downloaded.addAll(await dao.alreadyDownloadedAmong(
      [
        for (final l in group)
          (
            diveId: l.diveId,
            startTimeSeconds: l.startTimestamp,
            diveNumber: l.diveNumber,
          ),
      ],
      vendor: w.vendor,
      serial: w.serial,
    ));
  }

  final out = <DiveListing>[];
  for (final l in listed) {
    String? flag;
    if (stored.contains(l.diveId) || downloaded.contains(l.diveId)) {
      flag = kFitAlreadyStoredFlag;
    } else {
      final w = watchOf[l.diveId];
      if (w != null) {
        final other = await dao.overlappingDiveFromOtherComputer(
          startSeconds: l.startTimestamp,
          endSeconds: l.endTimestamp,
          vendor: w.vendor,
          serial: w.serial,
        );
        if (other != null) flag = 'Overlaps your ${other.label} dive';
      }
    }
    out.add(DiveListing(
      diveNumber: l.diveNumber,
      startTimestamp: l.startTimestamp,
      endTimestamp: l.endTimestamp,
      fingerprint: l.fingerprint,
      diveId: l.diveId,
      maxDepthMeters: l.maxDepthMeters,
      durationSeconds: l.durationSeconds,
      modelLabel: l.modelLabel,
      flag: flag ?? l.flag,
      preselected: flag == null && l.preselected,
    ));
  }
  return out;
}
