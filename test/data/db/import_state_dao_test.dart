import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/import_state_dao.dart';
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
}
