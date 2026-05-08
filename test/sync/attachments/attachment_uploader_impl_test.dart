import 'dart:convert';
import 'dart:io';

import 'package:ccrlogger/data/db/dive_attachments_dao.dart';
import 'package:ccrlogger/data/models/dive_attachment.dart';
import 'package:ccrlogger/sync/attachments/attachment_signer.dart';
import 'package:ccrlogger/sync/attachments/attachment_uploader_impl.dart';
import 'package:ccrlogger/sync/attachments/pending_upload_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:powersync/powersync.dart' hide SyncStatus;

import '../../_helpers/powersync_test_helper.dart';

/// Recorded HTTP requests across signer + R2 PUT, in order. Tests
/// inspect this list to assert the right calls happened with the
/// right shape.
class _Recorder {
  final List<({String method, Uri url, Map<String, String> headers, List<int> body})> calls = [];
}

http.Client _wireClient(_Recorder rec, {
  String objectKey = 'attachments/owner-1/d1/canonical.bin',
  Uri? r2PutUrl,
  int signerStatus = 200,
  int r2Status = 200,
}) {
  final put = r2PutUrl ?? Uri.parse('https://r2.example.com/put?sig=zzz');
  return MockClient.streaming((req, bodyStream) async {
    final bytes = await bodyStream.toBytes();
    // Lower-case header keys so case-insensitive lookups work in the
    // assertions below (BaseRequest.headers is case-insensitive but a
    // plain Map<String,String> copy is not).
    final headers = <String, String>{};
    req.headers.forEach((k, v) => headers[k.toLowerCase()] = v);
    rec.calls.add((
      method: req.method,
      url: req.url,
      headers: headers,
      body: bytes,
    ));
    if (req.method == 'POST' && req.url.path == '/sign-upload') {
      final body = jsonEncode({
        'object_key': objectKey,
        'upload_url': put.toString(),
        'expires_at': 1700000300,
      });
      return http.StreamedResponse(
        Stream.value(body.codeUnits),
        signerStatus,
        headers: {'content-type': 'application/json'},
      );
    }
    if (req.method == 'PUT' && req.url.toString() == put.toString()) {
      return http.StreamedResponse(
        Stream.value(const <int>[]),
        r2Status,
      );
    }
    return http.StreamedResponse(
      Stream.value('unexpected'.codeUnits),
      500,
    );
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PowerSyncDatabase db;
  late DiveAttachmentsDao dao;
  late FakeSessionSource session;
  late InMemoryPendingUploadStore pendingStore;
  late Directory tmpRoot;

  setUp(() async {
    db = await openPowerSyncForTest();
    session = FakeSessionSource()..setUserId('owner-1');
    dao = DiveAttachmentsDao(db, session);
    pendingStore = InMemoryPendingUploadStore();
    tmpRoot = await Directory.systemTemp.createTemp('ccrlogger_up_test_');
  });

  tearDown(() async {
    if (await tmpRoot.exists()) {
      await tmpRoot.delete(recursive: true);
    }
  });

  Future<File> writeTmp(String name, List<int> bytes) async {
    final f = File(p.join(tmpRoot.path, name));
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  Future<void> seedPendingRow(String id, {String mime = 'application/pdf'}) async {
    final now = DateTime.now();
    await dao.insertFile(FileAttachment(
      id: id,
      parentKind: DiveAttachmentParentKind.dive,
      parentId: 'd1',
      storageKey: 'pending:$id',
      mimeType: mime,
      uploadState: UploadState.pending,
      createdAt: now,
      updatedAt: now,
    ));
  }

  test('happy path: signs, PUTs with correct Content-Type, marks uploaded',
      () async {
    await seedPendingRow('f1', mime: 'application/pdf');
    final file = await writeTmp('scan.pdf', const [1, 2, 3, 4, 5]);

    final rec = _Recorder();
    final client = _wireClient(rec,
        objectKey: 'attachments/owner-1/d1/canonical.pdf');
    final signer = AttachmentSigner(
      baseUrl: 'https://signer.example.com',
      session: session,
      httpClient: client,
    );
    final uploader = AttachmentUploaderImpl(
      signer: signer,
      dao: dao,
      pendingStore: pendingStore,
      httpClient: client,
    );

    final progressEvents = <double>[];
    await uploader.upload(
      attachmentId: 'f1',
      diveId: 'd1',
      localFile: file,
      mimeType: 'application/pdf',
      onProgress: progressEvents.add,
    );

    // Two HTTP calls in order: POST sign-upload, then PUT to R2.
    expect(rec.calls.length, 2);
    expect(rec.calls[0].method, 'POST');
    expect(rec.calls[0].url.path, '/sign-upload');
    final signBody =
        jsonDecode(utf8.decode(rec.calls[0].body)) as Map<String, dynamic>;
    expect(signBody['dive_id'], 'd1');
    expect(signBody['filename'], 'scan.pdf');
    expect(signBody['mime_type'], 'application/pdf');
    expect(signBody['size_bytes'], 5);

    expect(rec.calls[1].method, 'PUT');
    expect(rec.calls[1].url.toString(), 'https://r2.example.com/put?sig=zzz');
    // The Content-Type on the PUT must match what the signer signed —
    // r2.ts bakes it into the signature, so a mismatch would 403.
    expect(rec.calls[1].headers['content-type'], 'application/pdf');
    expect(rec.calls[1].body, [1, 2, 3, 4, 5]);

    // DAO row flipped to uploaded with the canonical key + checksum.
    final row = await dao.get('f1') as FileAttachment;
    expect(row.uploadState, UploadState.uploaded);
    expect(row.storageKey, 'attachments/owner-1/d1/canonical.pdf');
    // SHA-256 of [1,2,3,4,5] is well-known.
    expect(
      row.checksumSha256,
      '74f81fe167d99b4cb41d6d0ccda82278caee9f3e2f25d5e5a3936ff3dcec60d0',
    );

    // Pending entry was cleared after success.
    expect(await pendingStore.pathFor('f1'), isNull);
    // Progress reported start and finish.
    expect(progressEvents.first, 0.0);
    expect(progressEvents.last, 1.0);
  });

  test('R2 PUT non-2xx → markUploadFailed and throw UploadFailedException',
      () async {
    await seedPendingRow('f1');
    final file = await writeTmp('scan.pdf', const [1, 2, 3]);

    final rec = _Recorder();
    final client = _wireClient(rec, r2Status: 500);
    final signer = AttachmentSigner(
      baseUrl: 'https://signer.example.com',
      session: session,
      httpClient: client,
    );
    final uploader = AttachmentUploaderImpl(
      signer: signer,
      dao: dao,
      pendingStore: pendingStore,
      httpClient: client,
    );

    await expectLater(
      uploader.upload(
        attachmentId: 'f1',
        diveId: 'd1',
        localFile: file,
        mimeType: 'application/pdf',
      ),
      throwsA(isA<UploadFailedException>()),
    );

    final row = await dao.get('f1') as FileAttachment;
    expect(row.uploadState, UploadState.failed);
    expect(row.uploadAttempts, 1);
    // Pending entry stays put — the bytes are still on local disk and
    // the next retry can find them.
    expect(await pendingStore.pathFor('f1'), file.path);
  });

  test('signer 401 → markUploadFailed and throw', () async {
    await seedPendingRow('f1');
    final file = await writeTmp('a.pdf', const [9]);

    final client = MockClient((req) async {
      if (req.url.path == '/sign-upload') {
        return http.Response(jsonEncode({'error': 'invalid_token'}), 401);
      }
      return http.Response('', 500);
    });
    final signer = AttachmentSigner(
      baseUrl: 'https://signer.example.com',
      session: session,
      httpClient: client,
    );
    final uploader = AttachmentUploaderImpl(
      signer: signer,
      dao: dao,
      pendingStore: pendingStore,
      httpClient: client,
    );

    await expectLater(
      uploader.upload(
        attachmentId: 'f1',
        diveId: 'd1',
        localFile: file,
        mimeType: 'application/pdf',
      ),
      throwsA(isA<UploadFailedException>()),
    );

    final row = await dao.get('f1') as FileAttachment;
    expect(row.uploadState, UploadState.failed);
  });

  test('retry succeeds when pending store has the path', () async {
    await seedPendingRow('f1');
    await dao.markUploadFailed('f1');

    final file = await writeTmp('scan.pdf', const [42, 42, 42]);
    await pendingStore.set('f1', file.path);

    final rec = _Recorder();
    final client = _wireClient(rec,
        objectKey: 'attachments/owner-1/d1/retried.pdf');
    final signer = AttachmentSigner(
      baseUrl: 'https://signer.example.com',
      session: session,
      httpClient: client,
    );
    final uploader = AttachmentUploaderImpl(
      signer: signer,
      dao: dao,
      pendingStore: pendingStore,
      httpClient: client,
    );

    final row = await dao.get('f1') as FileAttachment;
    await uploader.retry(row);

    final after = await dao.get('f1') as FileAttachment;
    expect(after.uploadState, UploadState.uploaded);
    expect(after.storageKey, 'attachments/owner-1/d1/retried.pdf');
    expect(rec.calls.length, 2);
  });

  test('retry with no cached path → markUploadFailed + throw', () async {
    await seedPendingRow('f1');
    await dao.markUploadFailed('f1');

    final client = MockClient((_) async => http.Response('', 500));
    final signer = AttachmentSigner(
      baseUrl: 'https://signer.example.com',
      session: session,
      httpClient: client,
    );
    final uploader = AttachmentUploaderImpl(
      signer: signer,
      dao: dao,
      pendingStore: pendingStore,
      httpClient: client,
    );

    final row = await dao.get('f1') as FileAttachment;
    await expectLater(
      uploader.retry(row),
      throwsA(isA<UploadFailedException>()
          .having((e) => e.message, 'message', contains('local file'))),
    );

    final after = await dao.get('f1') as FileAttachment;
    expect(after.uploadState, UploadState.failed);
    // Attempts bumped twice (once seeding, once on the retry).
    expect(after.uploadAttempts, 2);
  });

  test('retry with a path that no longer exists on disk → '
      'clears pending entry and throws', () async {
    await seedPendingRow('f1');
    await dao.markUploadFailed('f1');
    await pendingStore.set('f1', '/nonexistent/path/scan.pdf');

    final client = MockClient((_) async => http.Response('', 500));
    final signer = AttachmentSigner(
      baseUrl: 'https://signer.example.com',
      session: session,
      httpClient: client,
    );
    final uploader = AttachmentUploaderImpl(
      signer: signer,
      dao: dao,
      pendingStore: pendingStore,
      httpClient: client,
    );

    final row = await dao.get('f1') as FileAttachment;
    await expectLater(
      uploader.retry(row),
      throwsA(isA<UploadFailedException>()),
    );

    expect(await pendingStore.pathFor('f1'), isNull);
  });

  test('local file unreadable → markUploadFailed + throw', () async {
    await seedPendingRow('f1');
    final missing = File(p.join(tmpRoot.path, 'never_written.pdf'));

    final client = MockClient((_) async => http.Response('unused', 500));
    final signer = AttachmentSigner(
      baseUrl: 'https://signer.example.com',
      session: session,
      httpClient: client,
    );
    final uploader = AttachmentUploaderImpl(
      signer: signer,
      dao: dao,
      pendingStore: pendingStore,
      httpClient: client,
    );

    await expectLater(
      uploader.upload(
        attachmentId: 'f1',
        diveId: 'd1',
        localFile: missing,
        mimeType: 'application/pdf',
      ),
      throwsA(isA<UploadFailedException>()),
    );

    final row = await dao.get('f1') as FileAttachment;
    expect(row.uploadState, UploadState.failed);
  });
}
