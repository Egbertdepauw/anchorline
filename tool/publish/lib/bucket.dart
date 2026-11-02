/// The public downloads bucket (Cloudflare R2), as far as the publish command
/// needs it, and the AWS CLI implementation of it. `dart:` libraries and
/// `package:crypto` only, no Flutter.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'manifest.dart' show PublishError;

/// The bucket the downloads live in. Keys are paths like
/// `releases/manifest.json`. Methods throw [PublishError] when the bucket
/// cannot be reached or refuses the request.
abstract class Bucket {
  /// The text of the object at [key], or null when there is no such object.
  Future<String?> getText(String key);

  /// Uploads the local file at [path] to [key], replacing what is there.
  Future<void> putFile(String key, String path, {required String contentType});

  /// Uploads [text] (UTF-8) to [key], replacing what is there.
  Future<void> putText(
    String key,
    String text, {
    required String contentType,
    String? cacheControl,
  });

  /// Downloads the object at [key] and returns the sha256 of its bytes as
  /// lowercase hex, or null when there is no such object.
  Future<String?> sha256Of(String key);
}

/// The sha256 of a local file as lowercase hex, read as a stream.
Future<String> sha256OfFile(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

/// What [Process.run] looks like to [AwsCliBucket]; tests pass a fake.
typedef ProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
    });

/// A [Bucket] that shells out to the AWS CLI (`aws s3 cp`), pointed at R2's
/// S3 endpoint. The AWS CLI is preinstalled on GitHub's runners.
///
/// Credentials are not handled here: `aws` reads `AWS_ACCESS_KEY_ID` and
/// `AWS_SECRET_ACCESS_KEY` from the environment it inherits, and nothing in
/// this class copies, logs or passes them on. The error messages carry aws's
/// stderr, which does not contain credentials.
class AwsCliBucket implements Bucket {
  AwsCliBucket({
    required this.accountId,
    required this.bucket,
    ProcessRunner? runner,
    this.executable = 'aws',
  }) : _run = runner ?? Process.run;

  /// Reads `R2_ACCOUNT_ID` and `R2_BUCKET`, trimmed like the command's check
  /// that they are set. The caller has checked that both are.
  factory AwsCliBucket.fromEnvironment(
    Map<String, String> env, {
    ProcessRunner? runner,
  }) => AwsCliBucket(
    accountId: env['R2_ACCOUNT_ID']!.trim(),
    bucket: env['R2_BUCKET']!.trim(),
    runner: runner,
  );

  /// The Cloudflare account that owns the bucket (`R2_ACCOUNT_ID`).
  final String accountId;

  /// The bucket name (`R2_BUCKET`).
  final String bucket;

  /// The command to run; `aws` unless the CLI lives somewhere unusual.
  final String executable;

  final ProcessRunner _run;

  /// Added to the environment the aws process inherits. Newer AWS CLI
  /// versions add checksums to every request by default, and R2 rejects
  /// uploads that carry them.
  static const Map<String, String> _processEnvironment = {
    'AWS_REQUEST_CHECKSUM_CALCULATION': 'when_required',
    'AWS_RESPONSE_CHECKSUM_VALIDATION': 'when_required',
  };

  String get _endpoint => 'https://$accountId.r2.cloudflarestorage.com';

  String _uri(String key) => 's3://$bucket/$key';

  @override
  Future<String?> getText(String key) => _withTempDir((dir) async {
    final path = _tempFile(dir);
    if (!await _download(key, path)) return null;
    return File(path).readAsString();
  });

  @override
  Future<void> putFile(
    String key,
    String path, {
    required String contentType,
  }) async {
    // Absolute, so that a path that starts with a dash cannot be read as an
    // option.
    final result = await _cp(File(path).absolute.path, _uri(key), [
      '--content-type',
      contentType,
    ]);
    if (result.exitCode != 0) throw _failure('uploading $key', result);
  }

  @override
  Future<void> putText(
    String key,
    String text, {
    required String contentType,
    String? cacheControl,
  }) => _withTempDir((dir) async {
    final path = _tempFile(dir);
    await File(path).writeAsBytes(utf8.encode(text));
    final result = await _cp(path, _uri(key), [
      '--content-type',
      contentType,
      if (cacheControl != null) ...['--cache-control', cacheControl],
    ]);
    if (result.exitCode != 0) throw _failure('uploading $key', result);
  });

  @override
  Future<String?> sha256Of(String key) => _withTempDir((dir) async {
    final path = _tempFile(dir);
    if (!await _download(key, path)) return null;
    return sha256OfFile(path);
  });

  /// Downloads [key] to [path] with `s3api get-object`. False when the object
  /// is not there (see [_isMissingObject]); every other failure throws.
  ///
  /// Not `s3 cp`: that starts with a HEAD request, and a HEAD response has no
  /// body, so a missing key and a missing bucket look the same.
  Future<bool> _download(String key, String path) async {
    final result = await _aws([
      's3api',
      'get-object',
      '--bucket',
      bucket,
      '--key',
      key,
      path,
    ]);
    if (result.exitCode == 0) return true;
    if (_isMissingObject('${result.stderr}')) return false;
    throw _failure('downloading $key', result);
  }

  /// `aws s3 cp [from] [to]`, without the progress lines (they would only
  /// pile up in the captured output).
  Future<ProcessResult> _cp(
    String from,
    String to, [
    List<String> options = const [],
  ]) => _aws(['s3', 'cp', from, to, ...options, '--no-progress']);

  /// Runs the aws command [args] against the R2 endpoint.
  Future<ProcessResult> _aws(List<String> args) async {
    try {
      return await _run(executable, [
        ...args,
        '--endpoint-url',
        _endpoint,
        '--region',
        'auto',
      ], environment: _processEnvironment);
    } on ProcessException catch (e) {
      throw PublishError(
        'could not run the AWS CLI ($executable): ${e.message}',
      );
    }
  }

  PublishError _failure(String what, ProcessResult result) {
    final stderr = '${result.stderr}'.trim();
    return PublishError(
      '$what failed (aws exit code ${result.exitCode}): $stderr',
    );
  }
}

/// Whether aws's error output is the GetObject error `NoSuchKey`: the one
/// answer that means "the bucket answered and has no such object".
///
/// This is all that is read as absent. A GET error carries an XML body, so aws
/// names the error code, and `NoSuchBucket`, `AccessDenied`, a 403, bad
/// credentials and network trouble each say what they are. A bare `(404)` is
/// not enough: a HEAD request (what `aws s3 cp` and `s3api head-object` send)
/// has no body, so a missing key, a missing bucket and a bucket that lives
/// under another jurisdiction's endpoint all come back as just `(404)`. Reading
/// any of those as "absent" would make an empty list out of a mistake.
bool _isMissingObject(String stderr) => stderr.contains('(NoSuchKey)');

String _tempFile(Directory dir) => '${dir.path}${Platform.pathSeparator}object';

/// Runs [body] with a fresh temp directory and always deletes it afterwards.
Future<T> _withTempDir<T>(Future<T> Function(Directory dir) body) async {
  final dir = await Directory.systemTemp.createTemp('anchorline_publish_');
  try {
    return await body(dir);
  } finally {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // A leftover temp directory is not worth hiding the real outcome (or the
      // real error) behind.
    }
  }
}
