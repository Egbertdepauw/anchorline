import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/devices/dive_download_source.dart';
import 'package:ccrlogger/devices/fit/fit_file_source.dart';
import 'package:ccrlogger/devices/fit/fit_listing_marks.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/fit_test_support.dart';
import '../../_helpers/powersync_test_helper.dart';

class _Source implements FitDownloadSource {
  _Source(this.vendor, this.serial);

  final String vendor;
  final int serial;

  @override
  ({String vendor, int serial})? watchOf(String diveId) =>
      (vendor: vendor, serial: serial);

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

Uint8List _bytes(String hex) => Uint8List.fromList([
      for (var i = 0; i + 1 < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);

void main() {
  late AppDatabase db;
  tearDown(() => db.close());

  test('a second dive of one watch, starting under 60 s after a stored one '
      'with the same dive number, is not "Already in Anchorline"', () async {
    db = AppDatabase(NativeDatabase.memory());
    final rig = await openDiveDaoForTest(db);
    final dao = rig.dao;

    final first = fitDive();
    await dao.importDive(
        converted: first, rawBlob: fitBlob(), parserVersion: 1);
    final d = first.dive;
    final start = d.startTime.millisecondsSinceEpoch ~/ 1000;
    final end = d.endTime.millisecondsSinceEpoch ~/ 1000;
    final source = _Source(d.dcVendor!, d.dcSerial);

    DiveListing listing(String id, int offset, Uint8List fp) => DiveListing(
          diveNumber: d.dcDiveNumber,
          startTimestamp: start + offset,
          endTimestamp: end + offset,
          fingerprint: fp,
          diveId: id,
        );

    final storedAgain = listing(d.id, 0, _bytes(d.dcFingerprint ?? ''));
    final next = listing('another-dive', 30, _bytes('00ff10aa'));
    final marked = await markFitListings(dao, source, [storedAgain, next]);

    final byId = {for (final l in marked) l.diveId: l};
    expect(byId[d.id]!.flag, kFitAlreadyStoredFlag);
    expect(byId[d.id]!.preselected, isFalse);
    expect(byId['another-dive']!.flag, isNot(kFitAlreadyStoredFlag));
    expect(byId['another-dive']!.preselected, isTrue);
  });
}
