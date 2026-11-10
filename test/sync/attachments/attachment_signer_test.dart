import 'dart:convert';

import 'package:ccrlogger/sync/attachments/attachment_signer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../_helpers/powersync_test_helper.dart';

/// A FakeSessionSource subclass that lets us pin a specific access
/// token without going through the full setUserId() helper, which
/// hardcodes the token to 't'.
class _TokenSessionSource extends FakeSessionSource {
  _TokenSessionSource({String? token, String userId = 'test-user'}) {
    if (token != null) {
      setUserId(userId);
      // Replace the canned session with one that carries the requested
      // access token. The base class field is private so we re-route
      // through the public setter pattern: build via setUserId then
      // overwrite via clear+session is awkward, so we cheat with a
      // wrapper field below.
      _overrideToken = token;
    }
  }

  String? _overrideToken;

  @override
  get currentSession {
    final base = super.currentSession;
    if (base == null) return null;
    if (_overrideToken == null) return base;
    return base.copyWith(accessToken: _overrideToken);
  }
}

void main() {
  group('AttachmentSigner', () {
    test('asserts non-empty baseUrl', () {
      final session = FakeSessionSource()..setUserId('u1');
      expect(
        () => AttachmentSigner(baseUrl: '', session: session),
        throwsA(isA<AssertionError>()),
      );
    });

    test('strips trailing slash from baseUrl', () async {
      final session = FakeSessionSource()..setUserId('u1');
      Uri? hitUrl;
      final client = MockClient((req) async {
        hitUrl = req.url;
        return http.Response(
          jsonEncode({
            'object_key': 'attachments/u1/d1/abc.pdf',
            'upload_url': 'https://r2.example.com/put',
            'expires_at': 1700000000,
          }),
          200,
        );
      });
      final signer = AttachmentSigner(
        baseUrl: 'https://signer.example.com/',
        session: session,
        httpClient: client,
      );
      await signer.signUpload(
        diveId: 'd1',
        filename: 'a.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 100,
      );
      expect(hitUrl?.toString(), 'https://signer.example.com/sign-upload');
    });

    test('signUpload happy path parses response and sends correct body',
        () async {
      final session = FakeSessionSource()..setUserId('u1');
      Map<String, dynamic>? body;
      Map<String, String>? headers;
      final client = MockClient((req) async {
        headers = req.headers;
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'object_key': 'attachments/u1/d1/abc.pdf',
            'upload_url': 'https://r2.example.com/put?sig=xyz',
            'expires_at': 1700000300,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final signer = AttachmentSigner(
        baseUrl: 'https://signer.example.com',
        session: session,
        httpClient: client,
      );
      final res = await signer.signUpload(
        diveId: 'd1',
        filename: 'log.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 12345,
      );
      expect(res.objectKey, 'attachments/u1/d1/abc.pdf');
      expect(res.uploadUrl.toString(), 'https://r2.example.com/put?sig=xyz');
      expect(
        res.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(1700000300 * 1000, isUtc: true),
      );
      expect(body, {
        'dive_id': 'd1',
        'filename': 'log.pdf',
        'mime_type': 'application/pdf',
        'size_bytes': 12345,
      });
      expect(headers!['authorization'], 'Bearer t');
      expect(headers!['content-type'], contains('application/json'));
    });

    test('signDownload happy path parses response', () async {
      final session = FakeSessionSource()..setUserId('u1');
      final client = MockClient((req) async {
        expect(req.url.path, '/sign-download');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['object_key'], 'attachments/u1/d1/abc.pdf');
        return http.Response(
          jsonEncode({
            'download_url': 'https://r2.example.com/get?sig=xyz',
            'expires_at': 1700000400,
          }),
          200,
        );
      });
      final signer = AttachmentSigner(
        baseUrl: 'https://signer.example.com',
        session: session,
        httpClient: client,
      );
      final res = await signer.signDownload(
          objectKey: 'attachments/u1/d1/abc.pdf');
      expect(res.downloadUrl.toString(), 'https://r2.example.com/get?sig=xyz');
      expect(
        res.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(1700000400 * 1000, isUtc: true),
      );
    });

    test('deleteObject hits /delete with the object_key', () async {
      final session = FakeSessionSource()..setUserId('u1');
      String? path;
      Map<String, dynamic>? body;
      final client = MockClient((req) async {
        path = req.url.path;
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'ok': true}), 200);
      });
      final signer = AttachmentSigner(
        baseUrl: 'https://signer.example.com',
        session: session,
        httpClient: client,
      );
      await signer.deleteObject(objectKey: 'attachments/u1/d1/abc.pdf');
      expect(path, '/delete');
      expect(body, {'object_key': 'attachments/u1/d1/abc.pdf'});
    });

    test('401 throws SignerAuthException with body', () async {
      final session = FakeSessionSource()..setUserId('u1');
      final client = MockClient((_) async =>
          http.Response(jsonEncode({'error': 'invalid_token'}), 401));
      final signer = AttachmentSigner(
        baseUrl: 'https://signer.example.com',
        session: session,
        httpClient: client,
      );
      await expectLater(
        signer.signUpload(
          diveId: 'd1',
          filename: 'a.pdf',
          mimeType: 'application/pdf',
          sizeBytes: 1,
        ),
        throwsA(isA<SignerAuthException>().having(
          (e) => e.body, 'body', contains('invalid_token'))),
      );
    });

    test('non-2xx (4xx) throws SignerException with status + body', () async {
      final session = FakeSessionSource()..setUserId('u1');
      final client = MockClient((_) async => http.Response(
            jsonEncode({'error': 'mime_type not allowed'}),
            400,
          ));
      final signer = AttachmentSigner(
        baseUrl: 'https://signer.example.com',
        session: session,
        httpClient: client,
      );
      await expectLater(
        signer.signUpload(
          diveId: 'd1',
          filename: 'a.exe',
          mimeType: 'application/x-msdownload',
          sizeBytes: 1,
        ),
        throwsA(isA<SignerException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.body, 'body', contains('mime_type'))),
      );
    });

    test('non-2xx (5xx) throws SignerException', () async {
      final session = FakeSessionSource()..setUserId('u1');
      final client = MockClient((_) async => http.Response('boom', 503));
      final signer = AttachmentSigner(
        baseUrl: 'https://signer.example.com',
        session: session,
        httpClient: client,
      );
      await expectLater(
        signer.signDownload(objectKey: 'attachments/u1/d1/abc'),
        throwsA(isA<SignerException>()
            .having((e) => e.statusCode, 'statusCode', 503)),
      );
    });

    group('quota and refusals', () {
      AttachmentSigner signerWith(http.Response Function(http.Request) h) {
        final session = FakeSessionSource()..setUserId('u1');
        return AttachmentSigner(
          baseUrl: 'https://signer.example.com',
          session: session,
          httpClient: MockClient((req) async => h(req)),
        );
      }

      Future<SignUploadResponse> sign(AttachmentSigner s) => s.signUpload(
            diveId: 'd1',
            filename: 'a.pdf',
            mimeType: 'application/pdf',
            sizeBytes: 10,
          );

      const usageJson = {
        'used_bytes': 999999990,
        'limit_bytes': 1000000000,
        'used_files': 5,
        'limit_files': 1000,
      };

      test('413 quota_exceeded throws AttachmentQuotaExceededException',
          () async {
        final s = signerWith((_) => http.Response(
            jsonEncode({'error': 'quota_exceeded', ...usageJson}), 413));
        await expectLater(
          sign(s),
          throwsA(isA<AttachmentQuotaExceededException>()
              .having((e) => e.usage.usedBytes, 'usedBytes', 999999990)
              .having((e) => e.usage.limitFiles, 'limitFiles', 1000)),
        );
      });

      test('413 with malformed body is a plain SignerException', () async {
        for (final body in [
          'not json',
          jsonEncode({'error': 'quota_exceeded'}),
          jsonEncode({'error': 'too_big', ...usageJson}),
          jsonEncode({'error': 'quota_exceeded', ...usageJson, 'used_files': 'x'}),
        ]) {
          final s = signerWith((_) => http.Response(body, 413));
          await expectLater(
            sign(s),
            throwsA(isA<SignerException>()
                .having((e) => e.statusCode, 'statusCode', 413)),
          );
        }
      });

      test('429 throws AttachmentRateLimitedException regardless of body',
          () async {
        for (final body in [jsonEncode({'error': 'rate_limited'}), 'garbage']) {
          final s = signerWith((_) => http.Response(body, 429));
          await expectLater(
              sign(s), throwsA(isA<AttachmentRateLimitedException>()));
        }
      });

      test('503 uploads_disabled throws AttachmentUploadsDisabledException',
          () async {
        final s = signerWith((_) =>
            http.Response(jsonEncode({'error': 'uploads_disabled'}), 503));
        await expectLater(
            sign(s), throwsA(isA<AttachmentUploadsDisabledException>()));
      });

      test('503 with another body is a plain SignerException', () async {
        final s = signerWith((_) => http.Response('boom', 503));
        await expectLater(
          sign(s),
          throwsA(isA<SignerException>()
              .having((e) => e.statusCode, 'statusCode', 503)),
        );
      });

      test('success with usage fields parses usage', () async {
        final s = signerWith((_) => http.Response(
            jsonEncode({
              'object_key': 'k',
              'upload_url': 'https://r2.example.com/put',
              'expires_at': 1700000000,
              ...usageJson,
            }),
            200));
        final res = await sign(s);
        expect(res.usage!.limitFiles, 1000);
        expect(res.usage!.usedBytes, 999999990);
        expect(res.usage!.uploadsEnabled, isNull);
      });

      test('success without usage fields has null usage', () async {
        final s = signerWith((_) => http.Response(
            jsonEncode({
              'object_key': 'k',
              'upload_url': 'https://r2.example.com/put',
              'expires_at': 1700000000,
            }),
            200));
        expect((await sign(s)).usage, isNull);
      });

      test('tryParse rejects missing or non-int fields', () {
        expect(AttachmentUsage.tryParse({...usageJson}..remove('used_bytes')),
            isNull);
        expect(AttachmentUsage.tryParse({...usageJson, 'limit_bytes': '1'}),
            isNull);
        expect(AttachmentUsage.tryParse({...usageJson, 'limit_bytes': 1.5}),
            isNull);
      });

      test('fetchUsage posts to /usage and parses uploads_enabled', () async {
        String? path;
        Map<String, dynamic>? sent;
        final s = signerWith((req) {
          path = req.url.path;
          sent = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
              jsonEncode({...usageJson, 'uploads_enabled': false}), 200);
        });
        final u = await s.fetchUsage();
        expect(path, '/usage');
        expect(sent, isEmpty);
        expect(u.usedFiles, 5);
        expect(u.uploadsEnabled, isFalse);
      });

      test('fetchUsage without valid usage fields throws SignerException',
          () async {
        final s = signerWith((_) => http.Response(jsonEncode({'ok': true}), 200));
        await expectLater(s.fetchUsage(), throwsA(isA<SignerException>()));
      });
    });

    test('no session throws SignerNoSessionException', () async {
      final session = FakeSessionSource(); // no setUserId
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return http.Response('', 200);
      });
      final signer = AttachmentSigner(
        baseUrl: 'https://signer.example.com',
        session: session,
        httpClient: client,
      );
      await expectLater(
        signer.signUpload(
          diveId: 'd1',
          filename: 'a.pdf',
          mimeType: 'application/pdf',
          sizeBytes: 1,
        ),
        throwsA(isA<SignerNoSessionException>()),
      );
      expect(called, isFalse,
          reason: 'no http call should be made when there is no session');
    });

    test('Authorization header carries the *current* token (rotation)',
        () async {
      final session = _TokenSessionSource(token: 'first-token');
      final tokensSeen = <String>[];
      final client = MockClient((req) async {
        tokensSeen.add(req.headers['authorization'] ?? '');
        return http.Response(jsonEncode({'ok': true}), 200);
      });
      final signer = AttachmentSigner(
        baseUrl: 'https://signer.example.com',
        session: session,
        httpClient: client,
      );
      await signer.deleteObject(objectKey: 'attachments/test-user/d/x');
      session._overrideToken = 'rotated-token';
      await signer.deleteObject(objectKey: 'attachments/test-user/d/x');
      expect(tokensSeen, ['Bearer first-token', 'Bearer rotated-token']);
    });
  });
}
