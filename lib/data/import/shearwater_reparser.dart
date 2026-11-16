import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
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
    var refreshed = 0, failed = 0, skipped = 0;
    for (final c in candidates) {
      final marks = await (_drift.select(_drift.diveImportMarks)
            ..where((t) => t.diveId.equals(c.id)))
          .getSingleOrNull();
      if (marks?.reparseFailedVersion == kShearwaterParserVersion) {
        skipped++;
        continue;
      }
      // An empty row is what Subsurface copies carry; it is not a raw blob.
      final blob = await _dao.getRawBlob(c.id);
      if (blob == null || blob.isEmpty) {
        skipped++;
        continue;
      }
      try {
        if (c.dcModel < 0 || c.dcModel >= ShearwaterModel.values.length) {
          throw RangeError.index(c.dcModel, ShearwaterModel.values, 'dc_model');
        }
        final converted =
            await _parse(blob, c.dcModel, c.dcSerial, c.dcDiveNumber);
        final outcome = await _dao.refreshFromRawBlob(
          diveId: c.id,
          converted: converted,
          parserVersion: kShearwaterParserVersion,
        );
        switch (outcome) {
          case ImportOutcome.refreshed:
            refreshed++;
          case ImportOutcome.rejected:
            throw const UnusableParse();
          default:
            skipped++;
        }
      } catch (e, st) {
        failed++;
        await _markFailed(c.id);
        _report(e, st, 'reparse');
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

/// A [ShearwaterReparser.waitUntilSynced] for the app.
///
/// Signed out: completes `true` at once (nothing to wait for).
/// Signed in: completes `true` once the sync status shows `connected` and not
/// `downloading` with a `lastSyncedAt` after this call, so the dive list the
/// re-parse reads is this launch's, not last session's; `false` after
/// [timeout], and the re-parse then waits for the next launch.
Future<bool> Function() waitUntilSyncedFor({
  required bool Function() isSignedIn,
  required SyncStatusSource status,
  DateTime Function() now = DateTime.now,
  Duration timeout = const Duration(minutes: 2),
}) {
  return () async {
    if (!isSignedIn()) return true;
    final started = now();
    bool synced(SyncStatusSnapshot s) =>
        s.connected &&
        !s.downloading &&
        s.lastSyncedAt != null &&
        s.lastSyncedAt!.isAfter(started);
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
