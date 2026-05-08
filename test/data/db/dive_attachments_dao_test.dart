import 'package:ccrlogger/data/db/dive_attachments_dao.dart';
import 'package:ccrlogger/data/models/dive_attachment.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart' hide SyncStatus;

import '../../_helpers/powersync_test_helper.dart';

FileAttachment _file({
  required String id,
  required String diveId,
  String? title,
  int displayOrder = 0,
  String storageKey = 'attachments/u/d/x.pdf',
  String mimeType = 'application/pdf',
  int? sizeBytes = 2048,
  String? originalFilename = 'manual.pdf',
  DateTime? createdAt,
}) {
  final now = createdAt ?? DateTime.now();
  return FileAttachment(
    id: id,
    parentKind: DiveAttachmentParentKind.dive,
    parentId: diveId,
    title: title,
    displayOrder: displayOrder,
    storageKey: storageKey,
    mimeType: mimeType,
    sizeBytes: sizeBytes,
    originalFilename: originalFilename,
    createdAt: now,
    updatedAt: now,
  );
}

LinkAttachment _link({
  required String id,
  required String diveId,
  String? title,
  int displayOrder = 0,
  String url = 'https://example.com/dive-report',
  DateTime? createdAt,
}) {
  final now = createdAt ?? DateTime.now();
  return LinkAttachment(
    id: id,
    parentKind: DiveAttachmentParentKind.dive,
    parentId: diveId,
    title: title,
    displayOrder: displayOrder,
    url: url,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PowerSyncDatabase db;
  late FakeSessionSource session;
  late DiveAttachmentsDao dao;

  setUp(() async {
    db = await openPowerSyncForTest();
    session = FakeSessionSource()..setUserId('owner-1');
    dao = DiveAttachmentsDao(db, session);
  });

  group('listForDive', () {
    test('empty list when nothing attached', () async {
      expect(await dao.listForDive('d1'), isEmpty);
    });

    test('insertFile + listForDive round-trips all file fields', () async {
      final f = _file(
        id: 'a1',
        diveId: 'd1',
        title: 'Logbook scan',
        storageKey: 'attachments/owner-1/d1/abc.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 12345,
        originalFilename: 'scan.pdf',
      );
      await dao.insertFile(f);

      final list = await dao.listForDive('d1');
      expect(list, hasLength(1));
      final got = list.single;
      expect(got, isA<FileAttachment>());
      final file = got as FileAttachment;
      expect(file.id, 'a1');
      expect(file.parentKind, DiveAttachmentParentKind.dive);
      expect(file.parentId, 'd1');
      expect(file.title, 'Logbook scan');
      expect(file.storageKey, 'attachments/owner-1/d1/abc.pdf');
      expect(file.mimeType, 'application/pdf');
      expect(file.sizeBytes, 12345);
      expect(file.originalFilename, 'scan.pdf');
      expect(file.uploadState, UploadState.pending);
      expect(file.uploadAttempts, 0);
      expect(file.checksumSha256, isNull);
    });

    test('insertLink + listForDive round-trips url and title', () async {
      await dao.insertLink(_link(
        id: 'a2',
        diveId: 'd1',
        title: 'Site report',
        url: 'https://wrecks.example.com/foo',
      ));

      final list = await dao.listForDive('d1');
      expect(list, hasLength(1));
      final got = list.single;
      expect(got, isA<LinkAttachment>());
      final link = got as LinkAttachment;
      expect(link.title, 'Site report');
      expect(link.url, 'https://wrecks.example.com/foo');
    });

    test(
        'mixed list returns both kinds in display_order ASC then created_at DESC',
        () async {
      // display_order 0, oldest
      await dao.insertFile(_file(
        id: 'a-old0',
        diveId: 'd1',
        displayOrder: 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      ));
      // display_order 0, newer — should come before a-old0 inside the same
      // bucket because we sort created_at DESC.
      await dao.insertLink(_link(
        id: 'a-new0',
        diveId: 'd1',
        displayOrder: 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
      ));
      // display_order 1 — sorts after the 0-bucket regardless of age.
      await dao.insertLink(_link(
        id: 'a1',
        diveId: 'd1',
        displayOrder: 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(3000),
      ));

      final ids = (await dao.listForDive('d1')).map((a) => a.id).toList();
      expect(ids, ['a-new0', 'a-old0', 'a1']);
    });

    test('listForDive scopes to the requested dive', () async {
      await dao.insertFile(_file(id: 'a1', diveId: 'd1'));
      await dao.insertFile(_file(id: 'a2', diveId: 'd2'));

      final d1 = await dao.listForDive('d1');
      expect(d1.map((a) => a.id), ['a1']);
    });
  });

  group('upload state', () {
    test(
        'markUploaded flips state, stores checksum, rewrites storage_key, '
        'bumps version', () async {
      // Insert with a sentinel storage_key the way the notifier does, so we
      // can assert markUploaded swaps it for the Worker-supplied key.
      await dao.insertFile(_file(
        id: 'a1',
        diveId: 'd1',
        storageKey: 'pending:a1',
      ));
      final v1 = (await dao.get('a1'))!.version;

      await dao.markUploaded(
        'a1',
        checksumSha256: 'deadbeef',
        storageKey: 'attachments/owner-1/d1/abc.pdf',
      );
      final got = (await dao.get('a1'))! as FileAttachment;
      expect(got.uploadState, UploadState.uploaded);
      expect(got.checksumSha256, 'deadbeef');
      expect(got.storageKey, 'attachments/owner-1/d1/abc.pdf');
      expect(got.version, greaterThan(v1));
    });

    test('markUploadFailed flips state, increments attempts, bumps version',
        () async {
      await dao.insertFile(_file(id: 'a1', diveId: 'd1'));
      final v1 = (await dao.get('a1'))!.version;

      await dao.markUploadFailed('a1');
      var got = (await dao.get('a1'))! as FileAttachment;
      expect(got.uploadState, UploadState.failed);
      expect(got.uploadAttempts, 1);
      expect(got.version, greaterThan(v1));

      await dao.markUploadFailed('a1');
      got = (await dao.get('a1'))! as FileAttachment;
      expect(got.uploadAttempts, 2);
    });

    test('listPendingUploads returns pending+failed file rows, excludes uploaded and links',
        () async {
      // pending file
      await dao.insertFile(_file(id: 'pending', diveId: 'd1'));
      // failed file
      await dao.insertFile(_file(id: 'failed', diveId: 'd1'));
      await dao.markUploadFailed('failed');
      // uploaded file
      await dao.insertFile(_file(id: 'done', diveId: 'd1'));
      await dao.markUploaded(
        'done',
        checksumSha256: 'x',
        storageKey: 'attachments/owner-1/d1/done.pdf',
      );
      // a link — should never appear
      await dao.insertLink(_link(id: 'lnk', diveId: 'd1'));
      // a soft-deleted pending file — excluded
      await dao.insertFile(_file(id: 'gone', diveId: 'd1'));
      await dao.softDelete('gone');

      final ids =
          (await dao.listPendingUploads()).map((f) => f.id).toSet();
      expect(ids, {'pending', 'failed'});
    });
  });

  group('soft delete + restore', () {
    test('softDelete excludes from listForDive but get() still returns the row',
        () async {
      await dao.insertFile(_file(id: 'a1', diveId: 'd1'));
      await dao.softDelete('a1');

      expect(await dao.listForDive('d1'), isEmpty);
      final tomb = await dao.get('a1');
      expect(tomb, isNotNull);
      expect(tomb!.deletedAt, isNotNull);
    });

    test('restore clears deletedAt and re-includes', () async {
      await dao.insertFile(_file(id: 'a1', diveId: 'd1'));
      await dao.softDelete('a1');
      await dao.restore('a1');

      final list = await dao.listForDive('d1');
      expect(list.map((a) => a.id), ['a1']);
      expect(list.single.deletedAt, isNull);
    });

    test('softDelete and restore both bump version', () async {
      await dao.insertFile(_file(id: 'a1', diveId: 'd1'));
      final v1 = (await dao.get('a1'))!.version;

      await dao.softDelete('a1');
      final v2 = (await dao.get('a1'))!.version;
      expect(v2, greaterThan(v1));

      await dao.restore('a1');
      final v3 = (await dao.get('a1'))!.version;
      expect(v3, greaterThan(v2));
    });
  });

  group('updateMetadata', () {
    test('bumps version + updated_at, leaves untouched fields alone', () async {
      await dao.insertLink(_link(
        id: 'a1',
        diveId: 'd1',
        title: 'Old title',
        url: 'https://old.example.com',
      ));
      final before = (await dao.get('a1'))! as LinkAttachment;
      // Sleep so updated_at strictly advances.
      await Future<void>.delayed(const Duration(milliseconds: 5));

      await dao.updateMetadata('a1', title: const Value('New title'));

      final after = (await dao.get('a1'))! as LinkAttachment;
      expect(after.title, 'New title');
      // url left alone.
      expect(after.url, 'https://old.example.com');
      expect(after.version, greaterThan(before.version));
      expect(after.updatedAt.millisecondsSinceEpoch,
          greaterThan(before.updatedAt.millisecondsSinceEpoch));
    });

    test('explicit Value(null) clears the field', () async {
      await dao.insertFile(_file(
        id: 'a1',
        diveId: 'd1',
        title: 'Has a title',
      ));
      await dao.updateMetadata(
        'a1',
        title: const Value<String?>(null),
        description: const Value('added'),
      );
      final got = (await dao.get('a1'))!;
      expect(got.title, isNull);
      expect(got.description, 'added');
    });

    test('displayOrder updates and is reflected in list ordering', () async {
      await dao.insertFile(_file(id: 'a1', diveId: 'd1', displayOrder: 0));
      await dao.insertFile(_file(id: 'a2', diveId: 'd1', displayOrder: 0));
      await dao.updateMetadata('a1', displayOrder: 5);

      // a2 (display_order 0) should now precede a1 (display_order 5).
      final ids = (await dao.listForDive('d1')).map((a) => a.id).toList();
      expect(ids.first, 'a2');
      expect(ids.last, 'a1');
    });

    test('no-op when row does not exist', () async {
      // Should not throw.
      await dao.updateMetadata('does-not-exist',
          title: const Value('whatever'));
      expect(await dao.get('does-not-exist'), isNull);
    });
  });

  group('listStorageKeysForDive', () {
    test('returns only file rows\' keys, excludes links', () async {
      await dao.insertFile(_file(
        id: 'f1',
        diveId: 'd1',
        storageKey: 'attachments/owner-1/d1/one.pdf',
      ));
      await dao.insertFile(_file(
        id: 'f2',
        diveId: 'd1',
        storageKey: 'attachments/owner-1/d1/two.jpg',
      ));
      await dao.insertLink(_link(id: 'l1', diveId: 'd1'));

      final keys = await dao.listStorageKeysForDive('d1');
      expect(keys.toSet(), {
        'attachments/owner-1/d1/one.pdf',
        'attachments/owner-1/d1/two.jpg',
      });
    });

    test('includes soft-deleted file rows so cleanup can reap them',
        () async {
      await dao.insertFile(_file(
        id: 'f1',
        diveId: 'd1',
        storageKey: 'attachments/owner-1/d1/one.pdf',
      ));
      await dao.softDelete('f1');
      final keys = await dao.listStorageKeysForDive('d1');
      expect(keys, ['attachments/owner-1/d1/one.pdf']);
    });
  });

  group('listAllStorageKeys', () {
    test('returns file keys across every dive, excludes link rows',
        () async {
      await dao.insertFile(_file(
        id: 'f1',
        diveId: 'd1',
        storageKey: 'attachments/owner-1/d1/one.pdf',
      ));
      await dao.insertFile(_file(
        id: 'f2',
        diveId: 'd2',
        storageKey: 'attachments/owner-1/d2/two.jpg',
      ));
      await dao.insertLink(_link(id: 'l1', diveId: 'd3'));

      final keys = await dao.listAllStorageKeys();
      expect(keys.toSet(), {
        'attachments/owner-1/d1/one.pdf',
        'attachments/owner-1/d2/two.jpg',
      });
    });

    test('includes soft-deleted rows so the reset sweep reaps them',
        () async {
      await dao.insertFile(_file(
        id: 'f1',
        diveId: 'd1',
        storageKey: 'attachments/owner-1/d1/dead.pdf',
      ));
      await dao.softDelete('f1');
      final keys = await dao.listAllStorageKeys();
      expect(keys, ['attachments/owner-1/d1/dead.pdf']);
    });
  });

  group('owner_id stamping', () {
    test('insertFile stamps owner_id from the session', () async {
      await dao.insertFile(_file(id: 'a1', diveId: 'd1'));
      final row = await db.get(
        'SELECT owner_id FROM dive_attachments WHERE id = ?',
        ['a1'],
      );
      expect(row['owner_id'], 'owner-1');
    });

    test('insertLink stamps owner_id from the session', () async {
      await dao.insertLink(_link(id: 'a1', diveId: 'd1'));
      final row = await db.get(
        'SELECT owner_id FROM dive_attachments WHERE id = ?',
        ['a1'],
      );
      expect(row['owner_id'], 'owner-1');
    });

    test('insert without a signed-in session leaves owner_id null', () async {
      session.clear();
      await dao.insertFile(_file(id: 'a1', diveId: 'd1'));
      final row = await db.get(
        'SELECT owner_id FROM dive_attachments WHERE id = ?',
        ['a1'],
      );
      expect(row['owner_id'], isNull);
    });
  });
}
