/// Downloads attachment bytes from R2 via a Worker-signed GET URL,
/// staging them through an [AttachmentCache] so a second view (e.g.
/// open-then-share, or thumbnail then full-screen) doesn't re-fetch.
///
/// Flow:
///   1. Cache hit → return immediately, signer never called.
///   2. Cache miss → ask the [AttachmentSigner] for a presigned GET
///      URL, stream bytes into a tmpfile, optionally verify SHA-256,
///      then move the tmpfile into the cache.
///
/// Checksum verification is opt-in via [expectedSha256]. The DAO
/// stamps it on `markUploaded`, so subsequent fetches can pass it
/// through and detect a corrupt object — which would either be a
/// transport bug or an R2-side mutation, both of which warrant a
/// hard error rather than silently rendering bad bytes.
library;

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'attachment_cache.dart';
import 'attachment_signer.dart';

/// Thrown when an [expectedSha256] does not match the bytes that were
/// actually downloaded. Distinct from a generic IO error so callers
/// can surface a "file appears corrupted on the server" message.
class DownloadCorruptException implements Exception {
  final String storageKey;
  final String expected;
  final String actual;
  const DownloadCorruptException({
    required this.storageKey,
    required this.expected,
    required this.actual,
  });

  @override
  String toString() =>
      'DownloadCorruptException($storageKey): expected $expected, got $actual';
}

/// Thrown when R2 returns a non-2xx status to a presigned GET. The
/// response body is preserved for logging.
class DownloadFailedException implements Exception {
  final String storageKey;
  final int statusCode;
  final String body;
  const DownloadFailedException({
    required this.storageKey,
    required this.statusCode,
    required this.body,
  });

  @override
  String toString() =>
      'DownloadFailedException($storageKey): $statusCode $body';
}

class AttachmentDownloader {
  final AttachmentSigner _signer;
  final AttachmentCache _cache;
  final http.Client _http;

  AttachmentDownloader({
    required AttachmentSigner signer,
    required AttachmentCache cache,
    http.Client? httpClient,
  })  : _signer = signer,
        _cache = cache,
        _http = httpClient ?? http.Client();

  /// Returns a local file ready to read. Hits the cache first; on miss
  /// signs a download URL and pulls bytes into the cache.
  ///
  /// If [expectedSha256] is non-null and the bytes don't match, the
  /// tmpfile is deleted and [DownloadCorruptException] is thrown — we
  /// do *not* poison the cache with bad bytes.
  Future<File> fetch({
    required String storageKey,
    String? expectedSha256,
  }) async {
    final cached = await _cache.get(storageKey);
    if (cached != null) return cached;

    final signed = await _signer.signDownload(objectKey: storageKey);
    await _cache.init();

    // Stage into a sibling tmp directory of the cache root. Same
    // filesystem → cache.put can rename instead of copy.
    final tmpDir = await Directory.systemTemp.createTemp('ccrlogger_dl_');
    final tmpFile = File(p.join(tmpDir.path, 'bytes'));
    try {
      final response = await _http.get(signed.downloadUrl);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw DownloadFailedException(
          storageKey: storageKey,
          statusCode: response.statusCode,
          body: response.body,
        );
      }
      await tmpFile.writeAsBytes(response.bodyBytes, flush: true);

      if (expectedSha256 != null) {
        final actual = sha256.convert(response.bodyBytes).toString();
        if (actual != expectedSha256) {
          throw DownloadCorruptException(
            storageKey: storageKey,
            expected: expectedSha256,
            actual: actual,
          );
        }
      }
      // put() moves tmpFile into the cache.
      return await _cache.put(storageKey, tmpFile);
    } finally {
      // Clean up tmpDir. If put() succeeded, tmpFile is already gone
      // and the dir is empty. If anything threw, this still removes
      // the leftover tmpfile.
      if (await tmpDir.exists()) {
        try {
          await tmpDir.delete(recursive: true);
        } catch (_) {
          // Best effort — caller will have already seen the original error.
        }
      }
    }
  }

  /// Closes the underlying http client. Lifecycle parity with
  /// [AttachmentSigner.close].
  void close() {
    _http.close();
  }
}
