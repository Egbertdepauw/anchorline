import 'dart:isolate';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:fit_reader/fit_reader.dart';
import 'package:subsurface_core/subsurface_core.dart' show ConvertedDive;

import '../db/database.dart';
import '../db/dive_dao.dart';
import 'import_problem_reporter.dart';

/// Parses the FIT file inside one stored raw blob. Gets only sendable data
/// (the FIT bytes) so it can run in another isolate.
typedef FitParseRunner = Future<List<ConvertedDive>> Function(Uint8List fit);

/// The production [FitParseRunner]: the parse runs in a background isolate.
/// The [ConvertedDive]s that come back are plain Dart data, so they cross
/// the isolate boundary by copy.
Future<List<ConvertedDive>> defaultFitParseRunner(Uint8List fit) =>
    Isolate.run(() => mapFitFile(fit));

/// After a FIT reader update, re-parses each stored FIT dive from its local
/// raw blob and refreshes it in place ([DiveDao.refreshFromRawBlob]), so ids,
/// notes and cylinders are kept. Dives without a local raw blob (imported on
/// another device) are skipped: that device refreshes them and the refresh
/// syncs down. The shape of `ShearwaterReparser`, for `dc_family = -1`.
///
/// A file can hold several dives, so the one to refresh is picked by the
/// stored `dc_fingerprint`. Every dive is its own transaction, so a run that
/// is killed carries on at the next launch.
///
/// Failures are reported through [ImportProblemReporter] (type and stack
/// only, see the global Sentry redaction); no file name, serial or dive data
/// goes in.
class FitReparser {
  FitReparser({
    required DiveDao diveDao,
    required AppDatabase drift,
    required ImportProblemReporter report,
    required Future<bool> Function() waitUntilSynced,
    FitParseRunner? parse,
  })  : _dao = diveDao,
        _drift = drift,
        _report = report,
        _waitUntilSynced = waitUntilSynced,
        _parse = parse ?? defaultFitParseRunner;

  final DiveDao _dao;
  final AppDatabase _drift;
  final ImportProblemReporter _report;
  final Future<bool> Function() _waitUntilSynced;
  final FitParseRunner _parse;

  /// [skipped] counts candidates that were not tried: no usable local raw
  /// blob, or a failure already recorded for this reader version. When
  /// [_waitUntilSynced] gives up, nothing is touched and all three are 0.
  Future<({int refreshed, int failed, int skipped})> run() async {
    if (!await _waitUntilSynced()) return (refreshed: 0, failed: 0, skipped: 0);

    final candidates = await _dao.fitReparseCandidates(kFitParserVersion);
    // Nothing to do on most launches: skip the mark and blob scans.
    if (candidates.isEmpty) return (refreshed: 0, failed: 0, skipped: 0);
    final failedIds = {
      for (final r in await _drift.customSelect(
        'SELECT dive_id FROM dive_import_marks WHERE reparse_failed_version = ?',
        variables: [Variable.withInt(kFitParserVersion)],
      ).get())
        r.read<String>('dive_id'),
    };
    // An empty row is what Subsurface copies carry; it is not a raw blob.
    final blobIds = {
      for (final r in await _drift
          .customSelect('SELECT dive_id FROM dive_raw_blobs '
              'WHERE length(raw_blob) > 0')
          .get())
        r.read<String>('dive_id'),
    };
    var refreshed = 0, failed = 0, skipped = 0;
    for (final c in candidates) {
      if (failedIds.contains(c.id) || !blobIds.contains(c.id)) {
        skipped++;
        continue;
      }
      final blob = await _dao.getRawBlob(c.id);
      if (blob == null || blob.isEmpty) {
        skipped++;
        continue;
      }
      // Only these failures say the blob itself is bad, so only they mark
      // the dive: a blob that is no FIT envelope, a parse that throws, a
      // file without the stored dive, and a parse the refresh rejects.
      ConvertedDive? converted;
      try {
        final fingerprint = c.dcFingerprint;
        if (fingerprint == null) {
          throw ArgumentError('dive row without a fingerprint');
        }
        final dives = await _parse(FitEnvelope.decode(blob).fit);
        for (final d in dives) {
          if (d.dive.dcFingerprint == fingerprint) converted = d;
        }
        if (converted == null) {
          throw StateError('the stored file has no dive with this fingerprint');
        }
      } catch (e, st) {
        failed++;
        await _markFailed(c.id);
        _report(e, st, 'reparse');
        continue;
      }
      final ImportOutcome outcome;
      try {
        outcome = await _dao.refreshFromRawBlob(
          diveId: c.id,
          converted: converted,
          parserVersion: kFitParserVersion,
        );
      } catch (e, st) {
        // A write error or a closed database says nothing about the blob:
        // report once, stop, and let the next launch retry unmarked.
        _report(e, st, 'reparse');
        return (refreshed: refreshed, failed: failed, skipped: skipped);
      }
      switch (outcome) {
        case ImportOutcome.refreshed:
          refreshed++;
        case ImportOutcome.rejected:
          failed++;
          await _markFailed(c.id);
          _report(const UnusableParse(), StackTrace.current, 'reparse');
        default:
          skipped++;
      }
    }
    return (refreshed: refreshed, failed: failed, skipped: skipped);
  }

  Future<void> _markFailed(String diveId) async {
    try {
      await _drift.into(_drift.diveImportMarks).insertOnConflictUpdate(
            DiveImportMarksCompanion(
              diveId: Value(diveId),
              reparseFailedVersion: const Value(kFitParserVersion),
            ),
          );
    } catch (e, st) {
      // Worst case the dive is tried again next launch and reported again.
      _report(e, st, 'reparse');
    }
  }
}
