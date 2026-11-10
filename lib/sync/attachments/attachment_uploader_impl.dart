/// Concrete `AttachmentUploader` that pairs the [AttachmentSigner]
/// with `package:http`'s client to PUT bytes directly to R2 via a
/// presigned URL.
///
/// Lifecycle of one upload:
///   1. Read file bytes (bounded by the Worker's 25 MB cap, so RAM is
///      fine for v1) and SHA-256 them.
///   2. Ask the signer for a presigned PUT URL + canonical object key.
///   3. Stash the local file path in [PendingUploadStore] so a later
///      `retry(row)` can rediscover the bytes without the notifier.
///   4. PUT bytes to R2 with `Content-Type` matching the signature
///      (R2 returns 403 on mismatch — the signer baked the MIME into
///      the signed URL deliberately, see worker/src/r2.ts).
///   5. On 2xx, flip the row to `uploaded` via the DAO with the canonical
///      object_key + checksum; clear the pending entry.
///   6. On any failure (signer error, network error, R2 non-2xx), flip
///      the row to `failed` and rethrow [UploadFailedException] so the
///      notifier surfaces it.
///
/// A rate-limited signer call (429) is retried in place: up to
/// [AttachmentUploaderImpl.rateLimitRetries] re-signs,
/// [AttachmentUploaderImpl.rateLimitWait] apart, before the upload fails
/// as above with the [AttachmentRateLimitedException] as its cause.
///
/// Progress reporting: v1 uses `http.StreamedRequest` so the chunked-
/// stream sink emits progress callbacks roughly per chunk. The actual
/// resolution is dominated by `package:http`'s internal buffering — for
/// our 25 MB cap that's plenty granular.
library;

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../data/db/dive_attachments_dao.dart';
import '../../data/models/dive_attachment.dart';
import 'attachment_signer.dart';
import 'attachment_uploader.dart';
import 'pending_upload_store.dart';

/// Thrown when the upload pipeline can't deliver bytes to R2. The
/// underlying cause (signer error, http error, etc.) is preserved in
/// [cause] so callers can pattern-match if they care: the notifier
/// tells quota and uploads-disabled refusals apart this way.
class UploadFailedException implements Exception {
  final String message;
  final Object? cause;
  const UploadFailedException(this.message, {this.cause});

  @override
  String toString() =>
      cause == null ? 'UploadFailedException: $message'
                    : 'UploadFailedException: $message (cause: $cause)';
}

class AttachmentUploaderImpl implements AttachmentUploader {
  /// Re-signs after a 429 before giving up.
  static const rateLimitRetries = 3;

  /// Wait before each re-sign. The Worker allows 20 signs per 60 s, so
  /// a burst that hits the limit has room again well within a minute.
  static const rateLimitWait = Duration(seconds: 15);

  final AttachmentSigner _signer;
  final DiveAttachmentsDao _dao;
  final PendingUploadStore _pendingStore;
  final http.Client _http;
  final Future<void> Function(Duration) _rateLimitDelay;

  /// [rateLimitDelay] waits between re-signs after a 429; tests inject
  /// one that returns at once.
  AttachmentUploaderImpl({
    required AttachmentSigner signer,
    required DiveAttachmentsDao dao,
    required PendingUploadStore pendingStore,
    http.Client? httpClient,
    Future<void> Function(Duration)? rateLimitDelay,
  })  : _signer = signer,
        _dao = dao,
        _pendingStore = pendingStore,
        _http = httpClient ?? http.Client(),
        _rateLimitDelay = rateLimitDelay ?? Future<void>.delayed;

  @override
  Future<void> upload({
    required String attachmentId,
    required String diveId,
    required File localFile,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.0);

    // Read the bytes once. Worker caps the upload at 25 MB so a full
    // in-memory buffer is fine for v1; if we ever lift the cap we'd
    // switch to a streamed checksum + streamed PUT.
    final List<int> bytes;
    try {
      bytes = await localFile.readAsBytes();
    } catch (e) {
      await _markFailed(attachmentId);
      throw UploadFailedException(
          'failed to read local file ${localFile.path}',
          cause: e);
    }

    final checksum = sha256.convert(bytes).toString();
    final filename = _basename(localFile.path);

    // Stash the path *before* the network call so a crash mid-upload
    // still leaves enough metadata for the retry sweep to resume.
    await _pendingStore.set(attachmentId, localFile.path);

    SignUploadResponse signed;
    try {
      signed = await _signWithRateLimitRetry(
        diveId: diveId,
        filename: filename,
        mimeType: mimeType,
        sizeBytes: bytes.length,
      );
    } catch (e) {
      await _markFailed(attachmentId);
      throw UploadFailedException('signer failed', cause: e);
    }

    try {
      await _putBytes(
        url: signed.uploadUrl,
        bytes: bytes,
        mimeType: mimeType,
        onProgress: onProgress,
      );
    } catch (e) {
      await _markFailed(attachmentId);
      throw UploadFailedException('R2 PUT failed', cause: e);
    }

    try {
      await _dao.markUploaded(
        attachmentId,
        checksumSha256: checksum,
        storageKey: signed.objectKey,
      );
    } catch (e) {
      // The bytes are in R2 but we couldn't update the DAO row. Flip
      // to failed so the retry path is taken — markUploaded is
      // idempotent with respect to R2 (re-uploading the same bytes is
      // a no-op cost-wise) so this is safe.
      await _markFailed(attachmentId);
      throw UploadFailedException('DAO markUploaded failed', cause: e);
    }

    await _pendingStore.clear(attachmentId);
    onProgress?.call(1.0);
  }

  @override
  Future<void> retry(FileAttachment row) async {
    final path = await _pendingStore.pathFor(row.id);
    if (path == null) {
      // No cached bytes — the user picked the file in a previous app
      // session and the entry was lost (uninstall, prefs wipe, etc.).
      // Mark failed so the UI surfaces the unrecoverable state.
      await _markFailed(row.id);
      throw const UploadFailedException(
          'local file no longer cached for retry');
    }
    final file = File(path);
    if (!await file.exists()) {
      await _pendingStore.clear(row.id);
      await _markFailed(row.id);
      throw UploadFailedException(
          'local file missing on disk for retry: $path');
    }
    await upload(
      attachmentId: row.id,
      diveId: row.parentId,
      localFile: file,
      mimeType: row.mimeType,
    );
  }

  @override
  Future<void> discard(String attachmentId) =>
      _pendingStore.clear(attachmentId);

  /// Closes the underlying http client. The signer owns its own client
  /// (passed in at construction) — we don't close that here, the caller
  /// that created it should.
  void close() {
    _http.close();
  }

  // ── internals ───────────────────────────────────────────────────────

  Future<SignUploadResponse> _signWithRateLimitRetry({
    required String diveId,
    required String filename,
    required String mimeType,
    required int sizeBytes,
  }) async {
    for (var retries = 0;; retries++) {
      try {
        return await _signer.signUpload(
          diveId: diveId,
          filename: filename,
          mimeType: mimeType,
          sizeBytes: sizeBytes,
        );
      } on AttachmentRateLimitedException {
        if (retries >= rateLimitRetries) rethrow;
        await _rateLimitDelay(rateLimitWait);
      }
    }
  }

  Future<void> _markFailed(String id) async {
    // Best-effort: a DAO failure here is itself a problem, but we don't
    // want to mask the original upload error by rethrowing this one.
    try {
      await _dao.markUploadFailed(id);
    } catch (_) {
      // swallow — original cause will be rethrown by the caller
    }
  }

  /// PUTs [bytes] to [url] with the signed Content-Type header and
  /// reports progress via [onProgress]. Uses a [http.StreamedRequest]
  /// so we can fire incremental progress events instead of just 0/1.
  Future<void> _putBytes({
    required Uri url,
    required List<int> bytes,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async {
    final request = http.StreamedRequest('PUT', url)
      ..headers['Content-Type'] = mimeType
      ..contentLength = bytes.length;

    // Feed the bytes in 64 KiB chunks so the progress callback fires
    // a sensible number of times even on a small file. http handles
    // backpressure internally; the stream sink awaits as needed.
    const chunkSize = 64 * 1024;
    unawaited(() async {
      try {
        var sent = 0;
        for (var i = 0; i < bytes.length; i += chunkSize) {
          final end =
              (i + chunkSize) > bytes.length ? bytes.length : i + chunkSize;
          final chunk = bytes.sublist(i, end);
          request.sink.add(chunk);
          sent += chunk.length;
          if (onProgress != null && bytes.isNotEmpty) {
            onProgress(sent / bytes.length);
          }
        }
      } finally {
        request.sink.close();
      }
    }());

    final streamed = await _http.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UploadFailedException(
          'R2 returned ${response.statusCode}: ${response.body}');
    }
  }

  String _basename(String path) {
    // Avoid pulling package:path here for one call — keeps the upload
    // path standalone-runnable in non-Flutter contexts (e.g. headless
    // server-side reparse, if we ever go there).
    final i = path.lastIndexOf(Platform.pathSeparator);
    if (i < 0) {
      // Also tolerate Windows-style separators just in case the path
      // came from a synthetic File on a non-native FS.
      final j = path.lastIndexOf('/');
      if (j < 0) return path;
      return path.substring(j + 1);
    }
    return path.substring(i + 1);
  }
}
