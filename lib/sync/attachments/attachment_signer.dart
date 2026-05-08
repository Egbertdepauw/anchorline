/// Thin HTTP wrapper around the CCRLog attachments Worker.
///
/// The Worker (see `worker/src/index.ts`) owns three POST routes:
///   * `/sign-upload`   → mint a presigned R2 PUT URL
///   * `/sign-download` → mint a presigned R2 GET URL
///   * `/delete`        → delete an R2 object via the BUCKET binding
///
/// Each request must carry `Authorization: Bearer <supabase_jwt>`; the
/// signer reads the access token off the [SessionSource] immediately
/// before every call so that token rotation in Supabase's background
/// refresh is picked up without extra plumbing.
///
/// Errors:
///   * 401 → [SignerAuthException] (caller may prompt for sign-in)
///   * other non-2xx → [SignerException] with status + raw body
///   * IO / parse failures → bubble up as the underlying `Exception`
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../cloud/ccrlogger_backend_connector.dart' show SessionSource;

/// Successful response from `POST /sign-upload`.
class SignUploadResponse {
  /// Canonical R2 object key the Worker generated. The DAO's
  /// `markUploaded` rewrites the row's sentinel storage_key to this.
  final String objectKey;

  /// Presigned URL the client must `PUT` the bytes to. The presign was
  /// minted with the same Content-Type the signer was told about, so
  /// the upload PUT must echo that header verbatim or R2 returns 403.
  final Uri uploadUrl;

  /// Server-stamped Unix epoch seconds when the URL stops working.
  final DateTime expiresAt;

  const SignUploadResponse({
    required this.objectKey,
    required this.uploadUrl,
    required this.expiresAt,
  });
}

/// Successful response from `POST /sign-download`.
class SignDownloadResponse {
  final Uri downloadUrl;
  final DateTime expiresAt;

  const SignDownloadResponse({
    required this.downloadUrl,
    required this.expiresAt,
  });
}

/// Thrown on a 401 from the Worker. Distinct from [SignerException] so
/// the UI layer can hint at re-sign-in instead of a generic retry.
class SignerAuthException implements Exception {
  final String body;
  const SignerAuthException(this.body);

  @override
  String toString() => 'SignerAuthException: $body';
}

/// Thrown on any other non-2xx Worker response (4xx, 5xx). The raw
/// body is preserved so logging / debug UI can surface the Worker's
/// `error` JSON tag verbatim.
class SignerException implements Exception {
  final int statusCode;
  final String body;
  const SignerException(this.statusCode, this.body);

  @override
  String toString() => 'SignerException($statusCode): $body';
}

/// Thrown when the signer is asked to make a request but the
/// [SessionSource] currently has no access token. This is a programmer
/// error in production (the notifier should never call into the
/// signer without a session) but tests need to assert on it cleanly.
class SignerNoSessionException implements Exception {
  const SignerNoSessionException();
  @override
  String toString() => 'SignerNoSessionException: not signed in';
}

class AttachmentSigner {
  final String _baseUrl;
  final SessionSource _session;
  final http.Client _http;

  /// [baseUrl] must be the absolute Worker origin (e.g.
  /// `https://attachments.example.workers.dev`) without a trailing slash.
  /// We assert non-empty here rather than at every call site so that a
  /// misconfigured build (`ATTACHMENTS_SIGNER_URL` left empty) fails loud
  /// at construction time, not later when the user tries to attach a file.
  AttachmentSigner({
    required String baseUrl,
    required SessionSource session,
    http.Client? httpClient,
  })  : assert(baseUrl != '',
            'AttachmentSigner.baseUrl must not be empty; set --dart-define=ATTACHMENTS_SIGNER_URL=…'),
        _baseUrl = _stripTrailingSlash(baseUrl),
        _session = session,
        _http = httpClient ?? http.Client();

  static String _stripTrailingSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  Future<SignUploadResponse> signUpload({
    required String diveId,
    required String filename,
    required String mimeType,
    required int sizeBytes,
  }) async {
    final body = await _post('/sign-upload', {
      'dive_id': diveId,
      'filename': filename,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
    });
    return SignUploadResponse(
      objectKey: body['object_key'] as String,
      uploadUrl: Uri.parse(body['upload_url'] as String),
      expiresAt: _parseExpiresAt(body['expires_at']),
    );
  }

  Future<SignDownloadResponse> signDownload({
    required String objectKey,
  }) async {
    final body = await _post('/sign-download', {'object_key': objectKey});
    return SignDownloadResponse(
      downloadUrl: Uri.parse(body['download_url'] as String),
      expiresAt: _parseExpiresAt(body['expires_at']),
    );
  }

  Future<void> deleteObject({required String objectKey}) async {
    await _post('/delete', {'object_key': objectKey});
  }

  /// Closes the underlying http client. Call once at app shutdown if
  /// the caller owned the singleton; tests that pass their own client
  /// can no-op this.
  void close() {
    _http.close();
  }

  // ── internals ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final token = _session.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw const SignerNoSessionException();
    }
    final response = await _http.post(
      Uri.parse('$_baseUrl$path'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode == 401) {
      throw SignerAuthException(response.body);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SignerException(response.statusCode, response.body);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw SignerException(
          response.statusCode, 'expected JSON object, got: ${response.body}');
    }
    return decoded;
  }

  DateTime _parseExpiresAt(Object? raw) {
    // The Worker stamps `expires_at` as Unix epoch seconds (see r2.ts).
    // Tolerate ints and numeric strings — JSON deserialization can
    // surface either depending on Worker runtime version.
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw * 1000, isUtc: true);
    }
    if (raw is num) {
      return DateTime.fromMillisecondsSinceEpoch(
          (raw.toInt()) * 1000,
          isUtc: true);
    }
    if (raw is String) {
      final n = int.tryParse(raw);
      if (n != null) {
        return DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
      }
    }
    throw SignerException(
        200, 'unparseable expires_at: $raw');
  }
}
