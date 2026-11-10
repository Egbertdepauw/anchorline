import 'dart:async';

import 'package:ccrlogger/data/db/dive_attachments_dao.dart';
import 'package:ccrlogger/data/models/dive_attachment.dart';
import 'package:ccrlogger/sync/attachments/attachment_purger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart' hide SyncStatus;

import '../../_helpers/powersync_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 11, 10, 12);
  late PowerSyncDatabase db;
  late DiveAttachmentsDao dao;
  late List<String> deleted;
  late Future<void> Function(String) deleteFn;

  Future<void> addDeleted(String id, String key, Duration ago) async {
    final t = now.subtract(ago);
    await dao.insertFile(FileAttachment(
      id: id,
      parentKind: DiveAttachmentParentKind.dive,
      parentId: 'd1',
      storageKey: key,
      mimeType: 'application/pdf',
      createdAt: t,
      updatedAt: t,
    ));
    await db.execute(
      'UPDATE dive_attachments SET deleted_at = ? WHERE id = ?',
      [t.millisecondsSinceEpoch, id],
    );
  }

  Future<UploadState> stateOf(String id) async =>
      ((await dao.get(id))! as FileAttachment).uploadState;

  AttachmentPurger purger() =>
      AttachmentPurger(dao: dao, deleteObject: deleteFn, now: () => now);

  setUp(() async {
    db = await openPowerSyncForTest();
    final session = FakeSessionSource()..setUserId('owner-1');
    dao = DiveAttachmentsDao(db, session);
    deleted = [];
    deleteFn = (k) async => deleted.add(k);
  });

  test('deletes the object and marks the row purged', () async {
    await addDeleted('a1', 'attachments/u/d/a1.pdf', const Duration(hours: 25));

    expect(await purger().purgeDeleted(), 1);
    expect(deleted, ['attachments/u/d/a1.pdf']);
    expect(await stateOf('a1'), UploadState.purged);
  });

  test('rows younger than minAge are left alone', () async {
    await addDeleted('a1', 'k1', const Duration(hours: 23));

    expect(await purger().purgeDeleted(), 0);
    expect(deleted, isEmpty);
    expect(await stateOf('a1'), UploadState.pending);
  });

  test('pending: key is marked purged without a delete call', () async {
    await addDeleted('a1', 'pending:a1', const Duration(hours: 30));

    expect(await purger().purgeDeleted(), 1);
    expect(deleted, isEmpty);
    expect(await stateOf('a1'), UploadState.purged);
  });

  test('a failing delete leaves that row unpurged; others still purge',
      () async {
    await addDeleted('bad', 'k-bad', const Duration(hours: 30));
    await addDeleted('good', 'k-good', const Duration(hours: 30));
    deleteFn = (k) async {
      if (k == 'k-bad') throw Exception('boom');
      deleted.add(k);
    };

    expect(await purger().purgeDeleted(), 1);
    expect(deleted, ['k-good']);
    expect(await stateOf('bad'), UploadState.pending);
    expect(await stateOf('good'), UploadState.purged);
  });

  test('overlapping calls share one run', () async {
    await addDeleted('a1', 'k1', const Duration(hours: 30));
    await addDeleted('a2', 'k2', const Duration(hours: 30));
    final gate = Completer<void>();
    deleteFn = (k) async {
      await gate.future;
      deleted.add(k);
    };
    final p = purger();

    final first = p.purgeDeleted();
    final second = p.purgeDeleted();
    gate.complete();

    expect(await first, 2);
    expect(await second, 2);
    expect(deleted..sort(), ['k1', 'k2']);
  });

  test('minAge zero includes a row deleted a second ago', () async {
    await addDeleted('a1', 'k1', const Duration(seconds: 1));

    expect(await purger().purgeDeleted(minAge: Duration.zero), 1);
    expect(deleted, ['k1']);
  });

  test('hasPurgeable ignores the grace period', () async {
    final p = purger();
    expect(await p.hasPurgeable(), isFalse);
    await addDeleted('a1', 'k1', const Duration(seconds: 1));
    expect(await p.hasPurgeable(), isTrue);
    await p.purgeDeleted(minAge: Duration.zero);
    expect(await p.hasPurgeable(), isFalse);
  });
}
