/// Puts installers into the downloads bucket and keeps the two download lists
/// (`releases/manifest.json`, `nightly/manifest.json`) in step. Pure Dart,
/// `dart:` libraries and `package:crypto` only.
///
/// The list is what the website and the app read, so it is written last: a
/// publish that stops half way leaves objects in the bucket that nothing
/// points to, never a list that points to missing or wrong files.
library;

import 'dart:io';

import 'bucket.dart';
import 'manifest.dart';
import 'manifest.dart' as manifest show rollback;

/// The platforms an installer can be published for, in the order they are
/// uploaded and listed.
const List<String> platformKeys = ['windows-x64', 'linux-x64', 'macos'];

/// The bucket key of a lane's download list.
String manifestKey(Lane lane) => switch (lane) {
  Lane.releases => 'releases/manifest.json',
  Lane.nightly => 'nightly/manifest.json',
};

/// File extension (without the dot) to the content type the file is served
/// with.
const Map<String, String> _contentTypes = {
  'exe': 'application/vnd.microsoft.portable-executable',
  'AppImage': 'application/vnd.appimage',
  'dmg': 'application/x-apple-diskimage',
};

final RegExp _versionPattern = RegExp(r'^\d+\.\d+\.\d+$');

/// One installer on its way into the bucket.
class _Upload {
  _Upload(this.platformKey, this.path, this.key, this.contentType);

  final String platformKey;
  final String path;
  final String key;
  final String contentType;
}

class Publisher {
  /// [baseUrl] is where the bucket is served publicly; a trailing slash is
  /// ignored. [now] says when it is, for the entry date and the nightly
  /// retention. With [dryRun] the bucket is only read.
  Publisher(
    Bucket bucket, {
    required String baseUrl,
    required DateTime Function() now,
    bool dryRun = false,
  }) : _bucket = bucket,
       _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
       _now = now,
       _dryRun = dryRun;

  final Bucket _bucket;
  final String _baseUrl;
  final DateTime Function() _now;
  final bool _dryRun;

  /// Publishes [files] (platform key to local path) as [version] / [build] in
  /// [lane]'s list, and returns the list as written (as it would be written,
  /// for a dry run).
  ///
  /// Order: check the input, read the list (absent means empty), measure the
  /// files, build the new list (this is where a version or build that is
  /// already published is refused), upload every file, download each one
  /// again and compare checksums, and only then write the list. Everything
  /// that can be refused is refused before the first upload. [force] lets a
  /// release replace an entry of the same version; it has no meaning for
  /// nightlies.
  ///
  /// Throws [PublishError].
  Future<Manifest> publish({
    required Lane lane,
    required String version,
    required int build,
    required String notes,
    required Map<String, String> files,
    bool force = false,
  }) async {
    if (!_versionPattern.hasMatch(version)) {
      throw PublishError("version must look like 1.2.3, got '$version'");
    }
    if (build <= 0) {
      throw PublishError('build must be a positive integer, got $build');
    }
    final uploads = _plan(lane, version, build, files);

    final existing = await _read(lane);

    final entries = <String, FileEntry>{};
    for (final upload in uploads) {
      entries[upload.platformKey] = FileEntry(
        url: '$_baseUrl/${upload.key}',
        size: await File(upload.path).length(),
        sha256: await sha256OfFile(upload.path),
      );
    }
    final now = _now().toUtc();
    final entry = ReleaseEntry(
      version: version,
      build: build,
      date: _date(now),
      notes: notes,
      files: entries,
    );
    final updated = switch (lane) {
      Lane.releases => addRelease(existing, entry, force: force),
      Lane.nightly => addNightly(existing, entry, now: now),
    };
    if (_dryRun) return updated;

    for (final upload in uploads) {
      await _bucket.putFile(
        upload.key,
        upload.path,
        contentType: upload.contentType,
      );
    }
    for (final upload in uploads) {
      final expected = entries[upload.platformKey]!.sha256;
      final actual = await _bucket.sha256Of(upload.key);
      if (actual == null) {
        throw PublishError(
          '${upload.key} is not in the bucket after uploading it; '
          '${manifestKey(lane)} was not changed',
        );
      }
      if (actual.toLowerCase() != expected) {
        throw PublishError(
          '${upload.key} came out different after uploading '
          '(expected sha256 $expected, the bucket has $actual); '
          '${manifestKey(lane)} was not changed',
        );
      }
    }
    await _writeManifest(lane, updated);
    return updated;
  }

  /// Makes the earlier release [toVersion] the latest again. Only the list
  /// is written; no file is touched or deleted. Returns the list as written
  /// (as it would be written, for a dry run). Throws [PublishError], for one
  /// when [toVersion] is not in the list.
  Future<Manifest> rollback(String toVersion) async {
    final updated = manifest.rollback(await _read(Lane.releases), toVersion);
    if (!_dryRun) await _writeManifest(Lane.releases, updated);
    return updated;
  }

  /// Checks every file (known platform, known extension, exists) and decides
  /// where it goes, in [platformKeys] order whatever the order of [files].
  List<_Upload> _plan(
    Lane lane,
    String version,
    int build,
    Map<String, String> files,
  ) {
    if (files.isEmpty) {
      throw const PublishError('there are no files to publish');
    }
    final unknown = files.keys.where((k) => !platformKeys.contains(k)).toList();
    if (unknown.isNotEmpty) {
      throw PublishError(
        'unknown platform ${unknown.map((k) => "'$k'").join(', ')}; '
        'use ${platformKeys.join(', ')}',
      );
    }
    final uploads = <_Upload>[];
    for (final platformKey in platformKeys) {
      final path = files[platformKey];
      if (path == null) continue;
      final extension = _extension(path);
      final contentType = _contentTypes[extension];
      if (contentType == null) {
        throw PublishError(
          "cannot publish $path for $platformKey: the file extension "
          "'${extension ?? ''}' is not one of "
          '${_contentTypes.keys.map((e) => '.$e').join(', ')}',
        );
      }
      if (!FileSystemEntity.isFileSync(path)) {
        throw PublishError('the file for $platformKey does not exist: $path');
      }
      uploads.add(
        _Upload(
          platformKey,
          path,
          objectKey(
            lane: lane,
            version: version,
            build: build,
            platformKey: platformKey,
            extension: extension!,
          ),
          contentType,
        ),
      );
    }
    return uploads;
  }

  /// The lane's list as it is in the bucket; empty when there is none yet. A
  /// list that cannot be read stops the publish rather than being replaced.
  Future<Manifest> _read(Lane lane) async {
    final key = manifestKey(lane);
    final text = await _bucket.getText(key);
    if (text == null) return Manifest.empty();
    try {
      return Manifest.parse(text);
    } on PublishError catch (e) {
      throw PublishError('$key cannot be read: ${e.message}');
    }
  }

  Future<void> _writeManifest(Lane lane, Manifest m) => _bucket.putText(
    manifestKey(lane),
    m.encode(),
    contentType: 'application/json',
    cacheControl: 'no-cache',
  );
}

/// The extension of the file name in [path], without the dot; null when the
/// name has none.
String? _extension(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  return dot < 0 ? null : name.substring(dot + 1);
}

/// The calendar date of [utc] as `YYYY-MM-DD`.
String _date(DateTime utc) =>
    '${utc.year.toString().padLeft(4, '0')}-'
    '${utc.month.toString().padLeft(2, '0')}-'
    '${utc.day.toString().padLeft(2, '0')}';
