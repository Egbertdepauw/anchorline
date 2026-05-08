import 'dart:io';

import 'package:ccrlogger/data/db/dive_attachments_dao.dart';
import 'package:ccrlogger/data/models/dive_attachment.dart';
import 'package:ccrlogger/sync/attachments/attachment_uploader.dart';
import 'package:ccrlogger/ui/notifiers/dive_attachments_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart' hide SyncStatus;

import '../../_helpers/powersync_test_helper.dart';

class _FixedIdGenerator implements IdGenerator {
  final List<String> ids;
  int _i = 0;
  _FixedIdGenerator(this.ids);
  @override
  String next() {
    if (_i >= ids.length) {
      throw StateError('FixedIdGenerator ran out of ids');
    }
    return ids[_i++];
  }
}

typedef _UploadCall = ({
  String attachmentId,
  String diveId,
  String mimeType,
});

/// Records each [upload] / [retry] call and lets the test stub the
/// outcome. By default a successful upload calls
/// [DiveAttachmentsDao.markUploaded] with a canned key/checksum so the
/// row terminates in `uploaded`; failure stubs flip it to `failed`
/// and rethrow.
class _RecordingUploader implements AttachmentUploader {
  final DiveAttachmentsDao dao;
  final List<_UploadCall> uploads = [];
  final List<String> retries = [];

  /// Per-attachmentId override. If set, the function decides the
  /// outcome (call `markUploaded`/`markUploadFailed` itself or throw).
  /// If unset, [upload] succeeds with a canned storage_key.
  Future<void> Function(String attachmentId)? uploadStub;

  /// Override for [retry]. If unset, retries succeed by re-running
  /// the canned-success path.
  Future<void> Function(FileAttachment row)? retryStub;

  _RecordingUploader(this.dao);

  @override
  Future<void> upload({
    required String attachmentId,
    required String diveId,
    required File localFile,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async {
    uploads.add((
      attachmentId: attachmentId,
      diveId: diveId,
      mimeType: mimeType,
    ));
    final stub = uploadStub;
    if (stub != null) {
      await stub(attachmentId);
      return;
    }
    await dao.markUploaded(
      attachmentId,
      checksumSha256: 'cs-$attachmentId',
      storageKey: 'attachments/owner-1/$diveId/$attachmentId.bin',
    );
  }

  @override
  Future<void> retry(FileAttachment row) async {
    retries.add(row.id);
    final stub = retryStub;
    if (stub != null) {
      await stub(row);
      return;
    }
    await dao.markUploaded(
      row.id,
      checksumSha256: 'cs-${row.id}',
      storageKey: 'attachments/owner-1/${row.parentId}/${row.id}.bin',
    );
  }
}

PickedAttachmentFile _picked({
  String name = 'log.pdf',
  String mime = 'application/pdf',
  int size = 1024,
}) {
  // The fake uploader never reads the bytes, so a non-existent path
  // is fine here — File is a path wrapper, not an open handle.
  return PickedAttachmentFile(
    file: File('/tmp/$name'),
    originalFilename: name,
    mimeType: mime,
    sizeBytes: size,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PowerSyncDatabase db;
  late DiveAttachmentsDao dao;
  late _RecordingUploader uploader;

  setUp(() async {
    db = await openPowerSyncForTest();
    final session = FakeSessionSource()..setUserId('owner-1');
    dao = DiveAttachmentsDao(db, session);
    uploader = _RecordingUploader(dao);
  });

  test('load() populates list, sets loaded=true, notifies', () async {
    // Pre-seed two rows directly via the DAO.
    final now = DateTime.now();
    await dao.insertLink(LinkAttachment(
      id: 'l1',
      parentKind: DiveAttachmentParentKind.dive,
      parentId: 'd1',
      url: 'https://example.com/a',
      displayOrder: 0,
      createdAt: now,
      updatedAt: now,
    ));
    await dao.insertFile(FileAttachment(
      id: 'f1',
      parentKind: DiveAttachmentParentKind.dive,
      parentId: 'd1',
      storageKey: 'attachments/owner-1/d1/x.pdf',
      mimeType: 'application/pdf',
      displayOrder: 1,
      createdAt: now,
      updatedAt: now,
    ));

    final n = DiveAttachmentsNotifier(
      dao,
      uploader,
      idGenerator: _FixedIdGenerator(const []),
    );
    var notifyCount = 0;
    n.addListener(() => notifyCount++);

    expect(n.loaded, isFalse);
    await n.load('d1');

    expect(n.loaded, isTrue);
    expect(n.loading, isFalse);
    expect(n.error, isNull);
    expect(n.attachments.map((a) => a.id).toList(), ['l1', 'f1']);
    // load() notifies twice: once for the loading=true transition, once
    // when the fetch completes.
    expect(notifyCount, 2);
  });

  test('addLink inserts a link visible in attachments', () async {
    final n = DiveAttachmentsNotifier(
      dao,
      uploader,
      idGenerator: _FixedIdGenerator(['link-1']),
    );
    await n.load('d1');

    await n.addLink(
      url: 'https://wreck.example.com',
      title: 'Wreck report',
      description: 'PDF mirror',
    );

    expect(n.attachments, hasLength(1));
    final a = n.attachments.single;
    expect(a, isA<LinkAttachment>());
    final link = a as LinkAttachment;
    expect(link.id, 'link-1');
    expect(link.url, 'https://wreck.example.com');
    expect(link.title, 'Wreck report');
    expect(link.description, 'PDF mirror');
    expect(link.displayOrder, 0);
  });

  test(
      'addFile inserts pending row, kicks uploader, terminates uploaded after success',
      () async {
    final n = DiveAttachmentsNotifier(
      dao,
      uploader,
      idGenerator: _FixedIdGenerator(['file-1']),
    );
    await n.load('d1');

    await n.addFile(_picked(name: 'scan.pdf'));

    // The recording uploader's default stub flips the row to uploaded.
    expect(uploader.uploads, hasLength(1));
    expect(uploader.uploads.single.attachmentId, 'file-1');
    expect(uploader.uploads.single.diveId, 'd1');
    expect(uploader.uploads.single.mimeType, 'application/pdf');

    expect(n.attachments, hasLength(1));
    final a = n.attachments.single as FileAttachment;
    expect(a.id, 'file-1');
    expect(a.uploadState, UploadState.uploaded);
    expect(a.storageKey, 'attachments/owner-1/d1/file-1.bin');
    expect(a.checksumSha256, 'cs-file-1');
    expect(a.originalFilename, 'scan.pdf');
    expect(a.mimeType, 'application/pdf');
    expect(n.error, isNull);
  });

  test('addFile with a throwing uploader leaves the row in failed', () async {
    uploader.uploadStub = (id) async {
      await dao.markUploadFailed(id);
      throw StateError('network down');
    };

    final n = DiveAttachmentsNotifier(
      dao,
      uploader,
      idGenerator: _FixedIdGenerator(['file-1']),
    );
    await n.load('d1');

    await n.addFile(_picked());

    expect(n.attachments, hasLength(1));
    final a = n.attachments.single as FileAttachment;
    expect(a.uploadState, UploadState.failed);
    expect(a.uploadAttempts, 1);
    // The error is surfaced via the notifier's error accessor.
    expect(n.error, contains('network down'));
  });

  test('retryUpload re-runs uploader.retry on the row', () async {
    // Seed a failed file row directly.
    final now = DateTime.now();
    await dao.insertFile(FileAttachment(
      id: 'f1',
      parentKind: DiveAttachmentParentKind.dive,
      parentId: 'd1',
      storageKey: 'pending:f1',
      mimeType: 'image/jpeg',
      uploadState: UploadState.pending,
      createdAt: now,
      updatedAt: now,
    ));
    await dao.markUploadFailed('f1');

    final n = DiveAttachmentsNotifier(
      dao,
      uploader,
      idGenerator: _FixedIdGenerator(const []),
    );
    await n.load('d1');
    expect((n.attachments.single as FileAttachment).uploadState,
        UploadState.failed);

    await n.retryUpload('f1');

    expect(uploader.retries, ['f1']);
    expect((n.attachments.single as FileAttachment).uploadState,
        UploadState.uploaded);
  });

  test('softDelete removes from list, restore puts it back', () async {
    final n = DiveAttachmentsNotifier(
      dao,
      uploader,
      idGenerator: _FixedIdGenerator(['l1']),
    );
    await n.load('d1');
    await n.addLink(url: 'https://example.com');

    expect(n.attachments.map((a) => a.id), ['l1']);

    await n.softDelete('l1');
    expect(n.attachments, isEmpty);

    await n.restore('l1');
    expect(n.attachments.map((a) => a.id), ['l1']);
  });

  test('updateMetadata bumps title/description/url on a link', () async {
    final n = DiveAttachmentsNotifier(
      dao,
      uploader,
      idGenerator: _FixedIdGenerator(['l1']),
    );
    await n.load('d1');
    await n.addLink(url: 'https://old.example.com', title: 'Old');

    await n.updateMetadata(
      'l1',
      title: 'New',
      description: 'Now with words',
      url: 'https://new.example.com',
    );

    final link = n.attachments.single as LinkAttachment;
    expect(link.title, 'New');
    expect(link.description, 'Now with words');
    expect(link.url, 'https://new.example.com');
  });

  test('reorder rewrites display_order across rows', () async {
    final n = DiveAttachmentsNotifier(
      dao,
      uploader,
      idGenerator: _FixedIdGenerator(['l1', 'l2', 'l3']),
    );
    await n.load('d1');
    await n.addLink(url: 'https://a.example.com');
    await n.addLink(url: 'https://b.example.com');
    await n.addLink(url: 'https://c.example.com');

    // Note: addLink inserts in display_order increments of 1, but
    // the DAO sorts display_order ASC then created_at DESC. l1 at
    // displayOrder=0 sorts first, then l2 at 1, then l3 at 2.
    expect(n.attachments.map((a) => a.id), ['l1', 'l2', 'l3']);

    // Move l1 (index 0) to the end (newIndex = 3, ReorderableListView
    // convention: one past the slot when dragging down).
    await n.reorder(0, 3);
    expect(n.attachments.map((a) => a.id), ['l2', 'l3', 'l1']);
    // display_order has been rewritten to match the new positions.
    for (var i = 0; i < n.attachments.length; i++) {
      expect(n.attachments[i].displayOrder, i);
    }

    // Move the last (l1) back to the front.
    await n.reorder(2, 0);
    expect(n.attachments.map((a) => a.id), ['l1', 'l2', 'l3']);
  });
}
