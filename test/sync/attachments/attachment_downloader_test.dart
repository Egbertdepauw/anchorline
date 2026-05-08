import 'dart:convert';
import 'dart:io';

import 'package:ccrlogger/sync/attachments/attachment_cache.dart';
import 'package:ccrlogger/sync/attachments/attachment_downloader.dart';
import 'package:ccrlogger/sync/attachments/attachment_signer.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import '../../_helpers/powersync_test_helper.dart';

void main() {
  late Directory tmpRoot;
  late Directory cacheRoot;
  late AttachmentCache cache;

  setUp(() async {
    tmpRoot = await Directory.systemTemp.createTemp('ccrlogger_dl_test_');
    cacheRoot = Directory(p.join(tmpRoot.path, 'cache'));
    cache = AttachmentCache(rootDirectory: cacheRoot);
  });

  tearDown(() async {
    if (await tmpRoot.exists()) {
      await tmpRoot.delete(recursive: true);
    }
  });

  /// Builds a MockClient that handles both signer POSTs (returning the
  /// canned signed URL) and R2 GETs (returning [r2Bytes] / [r2Status]).
  /// [signerCalls] / [r2Calls] are out-params so tests can assert call
  /// counts without ceremony.
  http.Client buildClient({
    required List<int> r2Bytes,
    int r2Status = 200,
    required List<Uri> signerCalls,
    required List<Uri> r2Calls,
    Uri? signedUrl,
  }) {
    final url = signedUrl ?? Uri.parse('https://r2.example.com/get?sig=xyz');
    return MockClient((req) async {
      if (req.method == 'POST' && req.url.path == '/sign-download') {
        signerCalls.add(req.url);
        return http.Response(
          jsonEncode({
            'download_url': url.toString(),
            'expires_at': 1700000400,
          }),
          200,
        );
      }
      if (req.method == 'GET' && req.url.toString() == url.toString()) {
        r2Calls.add(req.url);
        return http.Response.bytes(r2Bytes, r2Status);
      }
      return http.Response('unexpected request: ${req.method} ${req.url}', 500);
    });
  }

  test('cache hit returns the cached file without calling the signer',
      () async {
    final session = FakeSessionSource()..setUserId('u1');

    // Pre-populate the cache via the public API.
    await cache.init();
    final stagingFile = File(p.join(tmpRoot.path, 'pre'))
      ..writeAsBytesSync([1, 2, 3]);
    await cache.put('attachments/u1/d1/abc.pdf', stagingFile);

    final signerCalls = <Uri>[];
    final r2Calls = <Uri>[];
    final client = buildClient(
        r2Bytes: const [],
        signerCalls: signerCalls,
        r2Calls: r2Calls);
    final signer = AttachmentSigner(
      baseUrl: 'https://signer.example.com',
      session: session,
      httpClient: client,
    );
    final downloader = AttachmentDownloader(
      signer: signer,
      cache: cache,
      httpClient: client,
    );

    final f = await downloader.fetch(
        storageKey: 'attachments/u1/d1/abc.pdf');
    expect(await f.readAsBytes(), [1, 2, 3]);
    expect(signerCalls, isEmpty,
        reason: 'cache hit should not contact the signer');
    expect(r2Calls, isEmpty,
        reason: 'cache hit should not contact R2');
  });

  test('cache miss signs, fetches, caches, returns', () async {
    final session = FakeSessionSource()..setUserId('u1');
    const payload = [9, 8, 7, 6, 5];
    final signerCalls = <Uri>[];
    final r2Calls = <Uri>[];
    final client = buildClient(
      r2Bytes: payload,
      signerCalls: signerCalls,
      r2Calls: r2Calls,
    );
    final signer = AttachmentSigner(
      baseUrl: 'https://signer.example.com',
      session: session,
      httpClient: client,
    );
    final downloader = AttachmentDownloader(
      signer: signer,
      cache: cache,
      httpClient: client,
    );

    final f = await downloader.fetch(
        storageKey: 'attachments/u1/d1/abc.pdf');
    expect(await f.readAsBytes(), payload);
    expect(signerCalls, hasLength(1));
    expect(r2Calls, hasLength(1));

    // Second fetch is a cache hit.
    final f2 = await downloader.fetch(
        storageKey: 'attachments/u1/d1/abc.pdf');
    expect(await f2.readAsBytes(), payload);
    expect(signerCalls, hasLength(1),
        reason: 'second fetch must hit the cache, not re-sign');
  });

  test('checksum mismatch throws DownloadCorruptException, '
      'cache stays empty', () async {
    final session = FakeSessionSource()..setUserId('u1');
    const payload = [1, 2, 3];
    final wrongChecksum = sha256.convert([9, 9, 9]).toString();
    final signerCalls = <Uri>[];
    final r2Calls = <Uri>[];
    final client = buildClient(
      r2Bytes: payload,
      signerCalls: signerCalls,
      r2Calls: r2Calls,
    );
    final signer = AttachmentSigner(
      baseUrl: 'https://signer.example.com',
      session: session,
      httpClient: client,
    );
    final downloader = AttachmentDownloader(
      signer: signer,
      cache: cache,
      httpClient: client,
    );

    await expectLater(
      downloader.fetch(
        storageKey: 'attachments/u1/d1/abc.pdf',
        expectedSha256: wrongChecksum,
      ),
      throwsA(isA<DownloadCorruptException>()),
    );
    expect(await cache.get('attachments/u1/d1/abc.pdf'), isNull,
        reason: 'corrupt download must not poison the cache');
  });

  test('matching checksum stores in cache and returns', () async {
    final session = FakeSessionSource()..setUserId('u1');
    const payload = [1, 2, 3, 4];
    final correctChecksum = sha256.convert(payload).toString();
    final signerCalls = <Uri>[];
    final r2Calls = <Uri>[];
    final client = buildClient(
      r2Bytes: payload,
      signerCalls: signerCalls,
      r2Calls: r2Calls,
    );
    final signer = AttachmentSigner(
      baseUrl: 'https://signer.example.com',
      session: session,
      httpClient: client,
    );
    final downloader = AttachmentDownloader(
      signer: signer,
      cache: cache,
      httpClient: client,
    );

    final f = await downloader.fetch(
      storageKey: 'attachments/u1/d1/abc.pdf',
      expectedSha256: correctChecksum,
    );
    expect(await f.readAsBytes(), payload);
  });

  test('R2 non-2xx throws DownloadFailedException', () async {
    final session = FakeSessionSource()..setUserId('u1');
    final signerCalls = <Uri>[];
    final r2Calls = <Uri>[];
    final client = buildClient(
      r2Bytes: const [],
      r2Status: 404,
      signerCalls: signerCalls,
      r2Calls: r2Calls,
    );
    final signer = AttachmentSigner(
      baseUrl: 'https://signer.example.com',
      session: session,
      httpClient: client,
    );
    final downloader = AttachmentDownloader(
      signer: signer,
      cache: cache,
      httpClient: client,
    );

    await expectLater(
      downloader.fetch(storageKey: 'attachments/u1/d1/missing'),
      throwsA(isA<DownloadFailedException>()
          .having((e) => e.statusCode, 'statusCode', 404)),
    );
  });
}
