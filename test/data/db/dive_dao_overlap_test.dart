import 'dart:io';
import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:subsurface_core/shearwater/parser/dive_converter.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';

import '../../_helpers/powersync_test_helper.dart';

const _serial = 0xB89641E4;

Uint8List _raw(int n) =>
    File('test/fixtures/dives/dive_$n.bin').readAsBytesSync();

ConvertedDive _fx(int n) => DiveConverter.convert(
      parsed: ShearwaterDiveParser(model: ShearwaterModel.petrel3)
          .parse(_raw(n)),
      dcSerial: _serial,
      dcDiveNumber: n,
      dcModel: ShearwaterModel.petrel3,
    );

void main() {
  late AppDatabase db;
  late DiveDao dao;
  late PowerSyncDatabase ps;
  late String id;
  late int start, end;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final rig = await openDiveDaoForTest(db);
    dao = rig.dao;
    ps = rig.ps;
    final c = _fx(718);
    id = c.dive.id;
    start = c.dive.startTime.millisecondsSinceEpoch ~/ 1000;
    end = c.dive.endTime.millisecondsSinceEpoch ~/ 1000;
    await dao.importDive(converted: c, rawBlob: _raw(718), parserVersion: 1);
  });
  tearDown(() => db.close());

  Future<({String id, String label})?> overlap({
    int? from,
    int? to,
    String vendor = 'Garmin',
    int serial = 1000000001,
  }) =>
      dao.overlappingDiveFromOtherComputer(
        startSeconds: from ?? start + 60,
        endSeconds: to ?? end - 60,
        vendor: vendor,
        serial: serial,
      );

  test('a Petrel dive overlapping the span is returned with label '
      '"Petrel 3"', () async {
    final hit = await overlap();
    expect(hit, isNotNull);
    expect(hit!.id, id);
    expect(hit.label, 'Petrel 3');

    // The span only has to cross the dive, not sit inside it.
    expect((await overlap(from: start - 600, to: start + 5))?.id, id);
    expect((await overlap(from: end - 5, to: end + 600))?.id, id);
  });

  test('the label is the Shearwater model name when the product is NULL',
      () async {
    await ps.execute('UPDATE dives SET dc_product = NULL WHERE id = ?', [id]);
    expect((await overlap())?.label, 'Petrel 3');
  });

  test('the same watch, a deleted dive or a dive that only touches the span '
      'is not', () async {
    // The same computer: a NULL vendor counts as Shearwater on a download,
    // and the vendor may be given as Shearwater.
    await ps.execute('UPDATE dives SET dc_vendor = NULL WHERE id = ?', [id]);
    expect(await overlap(vendor: kShearwaterVendor, serial: _serial), isNull);
    // Another Shearwater serial is another computer.
    expect(
        (await overlap(vendor: kShearwaterVendor, serial: 42))?.id, id);

    // A span that only touches the dive at either end.
    expect(await overlap(from: end, to: end + 600), isNull);
    expect(await overlap(from: start - 600, to: start), isNull);

    await ps.execute('UPDATE dives SET deleted_at = 5 WHERE id = ?', [id]);
    expect(await overlap(), isNull);
  });
}
