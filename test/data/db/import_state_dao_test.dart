import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/import_state_dao.dart';
import 'package:ccrlogger/devices/fingerprint_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ImportStateDao dao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = ImportStateDao(db);
  });

  tearDown(() async { await db.close(); });

  test('getLastFingerprint returns null for unknown serial', () async {
    final fp = await dao.getLastFingerprint('DEADBEEF');
    expect(fp, isNull);
  });

  test('saveLastFingerprint stores and retrieves fingerprint', () async {
    final fp = Uint8List.fromList([0x69, 0xE4, 0xA3, 0x56]);
    await dao.saveLastFingerprint('B89641E4', fp);
    final retrieved = await dao.getLastFingerprint('B89641E4');
    expect(retrieved, equals(fp));
  });

  test('saveLastFingerprint updates existing entry', () async {
    final fp1 = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);
    final fp2 = Uint8List.fromList([0x05, 0x06, 0x07, 0x08]);
    await dao.saveLastFingerprint('B89641E4', fp1);
    await dao.saveLastFingerprint('B89641E4', fp2);
    final retrieved = await dao.getLastFingerprint('B89641E4');
    expect(retrieved, equals(fp2));
  });

  test('different serials have independent fingerprints', () async {
    final fp1 = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);
    final fp2 = Uint8List.fromList([0x05, 0x06, 0x07, 0x08]);
    await dao.saveLastFingerprint('AAAA', fp1);
    await dao.saveLastFingerprint('BBBB', fp2);
    expect(await dao.getLastFingerprint('AAAA'), equals(fp1));
    expect(await dao.getLastFingerprint('BBBB'), equals(fp2));
  });

  test('fingerprintsWithPrefix returns only matching keys', () async {
    final a = Uint8List.fromList([1, 2]);
    final b = Uint8List.fromList([3, 4]);
    final c = Uint8List.fromList([5, 6]);
    await dao.saveLastFingerprint('libdc:7:100', a);
    await dao.saveLastFingerprint('libdc:7:200', b);
    await dao.saveLastFingerprint('libdc:8:100', c);
    await dao.saveLastFingerprint('B89641E4', c);
    // `_` and `%` are LIKE wildcards; the prefix is literal.
    await dao.saveLastFingerprint('libdcX7:300', c);

    final found = await dao.fingerprintsWithPrefix('libdc:7:');
    expect(found.keys.toSet(), {'libdc:7:100', 'libdc:7:200'});
    expect(found['libdc:7:100'], a);
    expect(found['libdc:7:200'], b);
    expect(await dao.fingerprintsWithPrefix('libdc:9:'), isEmpty);
    expect(await dao.fingerprintsWithPrefix('libdc_7:'), isEmpty);
  });

  test('the dao is a FingerprintStore', () {
    expect(dao, isA<FingerprintStore>());
  });
}
