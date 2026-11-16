import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:subsurface_core/shearwater/parser/dive_converter.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';

import '../../shearwater/parser/dive_parser.dart';
import '../../shearwater/parser/parser_version.dart';
import '../../sync/cloud/sync_status_source.dart';
import '../db/database.dart';
import '../db/dive_dao.dart';
import 'import_problem_reporter.dart';

/// Parses and converts one raw blob. Gets only sendable data so it can run in
/// another isolate.
typedef ParseRunner = Future<ConvertedDive> Function(
    Uint8List bytes, int modelIndex, int serial, int diveNumber);

ConvertedDive _parseAndConvert(
    Uint8List bytes, int modelIndex, int serial, int diveNumber) {
  final model = ShearwaterModel.values[modelIndex];
  final parsed = ShearwaterDiveParser(model: model).parse(bytes);
  return DiveConverter.convert(
    parsed: parsed,
    dcSerial: serial,
    dcDiveNumber: diveNumber,
    dcModel: model,
  );
}

/// The production [ParseRunner]: parse and conversion run in a background
/// isolate. The arguments are bytes and ints; the [ConvertedDive] that comes
/// back is plain Dart data (no closures, no native handles), so it crosses the
/// isolate boundary by copy.
Future<ConvertedDive> defaultParseRunner(
        Uint8List bytes, int modelIndex, int serial, int diveNumber) =>
    Isolate.run(() => _parseAndConvert(bytes, modelIndex, serial, diveNumber));

/// After a reader update, re-parses each stored Shearwater dive from its local
/// raw blob and refreshes it in place ([DiveDao.refreshFromRawBlob]), so ids,
/// notes and cylinders are kept. Dives without a local raw blob (imported on
/// another device) are skipped: that device refreshes them and the refresh
/// syncs down.
///
/// Every dive is its own transaction, so a run that is killed carries on at
/// the next launch: refreshed dives are no longer below the current version.
class ShearwaterReparser {
  ShearwaterReparser({
    required DiveDao diveDao,
    required AppDatabase drift,
    required ImportProblemReporter report,
    required Future<bool> Function() waitUntilSynced,
    ParseRunner? parse,
  })  : _dao = diveDao,
        _drift = drift,
        _report = report,
        _waitUntilSynced = waitUntilSynced,
        _parse = parse ?? defaultParseRunner;

  final DiveDao _dao;
  final AppDatabase _drift;
  final ImportProblemReporter _report;
  final Future<bool> Function() _waitUntilSynced;
  final ParseRunner _parse;

  /// [skipped] counts candidates that were not tried: no usable local raw
  /// blob, or a failure already recorded for this reader version. When
  /// [_waitUntilSynced] gives up, nothing is touched and all three are 0.
  Future<({int refreshed, int failed, int skipped})> run() async {
    if (!await _waitUntilSynced()) return (refreshed: 0, failed: 0, skipped: 0);

    final candidates = await _dao.reparseCandidates(kShearwaterParserVersion);
    final failedIds = {
      for (final r in await _drift.customSelect(
        'SELECT dive_id FROM dive_import_marks WHERE reparse_failed_version = ?',
        variables: [Variable.withInt(kShearwaterParserVersion)],
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
      // the dive: a parse that throws, a model index or identity this build
      // cannot use, and a parse the refresh rejects.
      ConvertedDive? converted;
      try {
        final model = c.dcModel, serial = c.dcSerial, number = c.dcDiveNumber;
        if (model == null || serial == null || number == null) {
          throw ArgumentError('dive row without model, serial or number');
        }
        if (model < 0 || model >= ShearwaterModel.values.length) {
          throw RangeError.index(model, ShearwaterModel.values, 'dc_model');
        }
        converted = await _parse(blob, model, serial, number);
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
          parserVersion: kShearwaterParserVersion,
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
        case ImportOutcome.unchanged:
          skipped++;
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
              reparseFailedVersion: const Value(kShearwaterParserVersion),
            ),
          );
    } catch (e, st) {
      // Worst case the dive is tried again next launch and reported again.
      _report(e, st, 'reparse');
    }
  }
}

/// What the sync status looked like before this launch's sync could start.
/// Capture it before `CloudSyncCoordinator.start()`: a first sync that
/// finishes before the wait begins would otherwise read as the previous
/// session's value and never count.
class SyncBaseline {
  const SyncBaseline({required this.startedAt, required this.lastSyncedAt});

  /// The instant the baseline was taken.
  final DateTime startedAt;

  /// `lastSyncedAt` at that instant (persisted from an earlier session).
  final DateTime? lastSyncedAt;

  factory SyncBaseline.capture(SyncStatusSource status,
          {DateTime Function() now = DateTime.now}) =>
      SyncBaseline(startedAt: now(), lastSyncedAt: status.currentStatus.lastSyncedAt);
}

/// A [ShearwaterReparser.waitUntilSynced] for the app.
///
/// Signed out: completes `true` at once (nothing to wait for).
/// Signed in: completes `true` once the sync status shows `connected` and not
/// `downloading` with a `lastSyncedAt` after this call, so the dive list the
/// re-parse reads is this launch's, not last session's; `false` after
/// [timeout], and the re-parse then waits for the next launch.
///
/// [baseline] is taken before sync starts; without it the start and the
/// previous value are read when the returned function is called.
Future<bool> Function() waitUntilSyncedFor({
  SyncBaseline? baseline,
  required bool Function() isSignedIn,
  required SyncStatusSource status,
  DateTime Function() now = DateTime.now,
  Duration timeout = const Duration(minutes: 2),
}) {
  return () async {
    if (!isSignedIn()) return true;
    // PowerSync builds lastSyncedAt from whole seconds, so compare against
    // the start rounded down to the second. The value present at the start
    // belongs to an earlier session (even one under a second ago) and never
    // counts.
    final startedAt = baseline?.startedAt ?? now();
    final startedSecond = DateTime.fromMillisecondsSinceEpoch(
        startedAt.millisecondsSinceEpoch ~/ 1000 * 1000,
        isUtc: startedAt.isUtc);
    final previous =
        baseline != null ? baseline.lastSyncedAt : status.currentStatus.lastSyncedAt;
    bool synced(SyncStatusSnapshot s) =>
        s.connected &&
        !s.downloading &&
        s.lastSyncedAt != null &&
        !s.lastSyncedAt!.isBefore(startedSecond) &&
        s.lastSyncedAt != previous;
    if (synced(status.currentStatus)) return true;
    final done = Completer<bool>();
    final sub = status.statusStream.listen((s) {
      if (!done.isCompleted && synced(s)) done.complete(true);
    });
    final timer = Timer(timeout, () {
      if (!done.isCompleted) done.complete(false);
    });
    try {
      return await done.future;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  };
}
