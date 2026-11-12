/// Puts installers into the downloads bucket and keeps the two download lists
/// (`releases/manifest.json`, `nightly/manifest.json`) in step. Pure Dart,
/// `dart:` libraries and `package:crypto` only.
///
/// The list is what the website and the app read, so it is written last: a
/// publish that stops half way leaves objects in the bucket that nothing
/// points to, never a list that points to missing or wrong files.
///
/// The one exception is a forced re-publish of a version that is already
/// listed. Its files are overwritten before the list changes, so if that run
/// fails half way the list keeps describing the old bytes (size and sha256) of
/// files that may already be the new ones, until the command is run again.
/// The edge may also keep serving a replaced file from its cache: after a
/// forced re-publish, purge the Cloudflare cache for the replaced URLs.
///
/// Publishing what is already published, byte for byte, is not an error: it
/// changes nothing and says so. A re-run of a delivery job (or a list write
/// that reached R2 but timed out on the client) therefore finishes instead of
/// being refused.
///
/// A list is updated by reading it, changing it and writing it back, with no
/// lock. Two publishes to the same lane at the same time can lose one of the
/// changes. CI runs one publish job per lane at a time; do not run the command
/// by hand while one is running.
library;

import 'dart:io';

import 'bucket.dart';
import 'manifest.dart';
import 'manifest.dart' as manifest show rollback;

/// The platforms an installer can be published for, in the order they are
/// uploaded and listed.
const List<String> platformKeys = ['windows-x64', 'linux-x64', 'macos'];

/// The platforms a release has, and only those: a release is published for
/// Windows and Linux together (macOS comes from the stores). A nightly may
/// have any non-empty subset of [platformKeys].
const List<String> releasePlatformKeys = ['windows-x64', 'linux-x64'];

/// The bucket key of a lane's download list.
String manifestKey(Lane lane) => switch (lane) {
  Lane.releases => 'releases/manifest.json',
  Lane.nightly => 'nightly/manifest.json',
};

/// The file extension (without the dot) each platform's installer has.
const Map<String, String> _platformExtensions = {
  'windows-x64': 'exe',
  'linux-x64': 'AppImage',
  'macos': 'dmg',
};

/// File extension (without the dot) to the content type the file is served
/// with.
const Map<String, String> _contentTypes = {
  'exe': 'application/vnd.microsoft.portable-executable',
  'AppImage': 'application/vnd.appimage',
  'dmg': 'application/x-apple-diskimage',
};

/// One installer on its way into the bucket.
class _Upload {
  _Upload(this.platformKey, this.path, this.key, this.contentType);

  final String platformKey;
  final String path;
  final String key;
  final String contentType;
}

/// What [Publisher.publish] did.
class PublishResult {
  const PublishResult(this.manifest, {this.alreadyPublished = false});

  /// The list as written (as it would be written, for a dry run). When
  /// [alreadyPublished] is set, the list as it is in the bucket, unchanged.
  final Manifest manifest;

  /// The lane already listed this version (release) or build (nightly) with
  /// exactly these files, so nothing was uploaded or written.
  final bool alreadyPublished;
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
  /// A release has exactly [releasePlatformKeys]; a nightly any non-empty
  /// subset of [platformKeys].
  ///
  /// Order: check the input, read the list (absent means empty), measure the
  /// files, build the new list (this is where a version or build that is
  /// already published is refused), upload every file, download each one
  /// again and compare checksums, and only then write the list. Everything
  /// that can be refused is refused before the first upload. [force] lets a
  /// release replace an entry of the same version; nightlies refuse it.
  ///
  /// If the lane already lists this version (release) or build (nightly) with
  /// the same build number, the same platform keys, and the same url, size and
  /// sha256 for each, nothing is uploaded or written (also with [force], also
  /// in a dry run) and the result says [PublishResult.alreadyPublished]. Any
  /// difference is refused as above.
  ///
  /// Throws [PublishError].
  Future<PublishResult> publish({
    required Lane lane,
    required String version,
    required int build,
    required String notes,
    required Map<String, String> files,
    bool force = false,
  }) async {
    if (force && lane == Lane.nightly) {
      throw const PublishError('force only applies to releases, not nightlies');
    }
    if (!versionPattern.hasMatch(version)) {
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
    if (_isListed(existing, version, build, entries)) {
      return PublishResult(existing, alreadyPublished: true);
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
    if (_dryRun) return PublishResult(updated);

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
    return PublishResult(updated);
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

  /// Checks every file (known platform, the extension that platform's
  /// installer has, exists) and decides where it goes, in [platformKeys] order
  /// whatever the order of [files].
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
    if (lane == Lane.releases) {
      final missing = releasePlatformKeys.where((k) => !files.containsKey(k));
      final extra = files.keys.where((k) => !releasePlatformKeys.contains(k));
      if (missing.isNotEmpty || extra.isNotEmpty) {
        final problems = [
          if (missing.isNotEmpty) 'missing ${missing.join(', ')}',
          if (extra.isNotEmpty) 'not a release download: ${extra.join(', ')}',
        ];
        throw PublishError(
          'a release has exactly ${releasePlatformKeys.join(' and ')} '
          '(${problems.join('; ')})',
        );
      }
    }
    final uploads = <_Upload>[];
    for (final platformKey in platformKeys) {
      final path = files[platformKey];
      if (path == null) continue;
      final extension = _platformExtensions[platformKey]!;
      if (_extension(path) != extension) {
        throw PublishError(
          'cannot publish $path for $platformKey: the file has to end in '
          '.$extension',
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
            extension: extension,
          ),
          _contentTypes[extension]!,
        ),
      );
    }
    return uploads;
  }

  /// Whether [existing] already lists what this run would publish: an entry
  /// with this [version] and [build] and the same platform keys, with the same
  /// url, size and sha256 for each key as [files]. For a release that is the
  /// entry of this version; for a nightly, the entry of this build (a nightly
  /// of the same build but another version has other URLs). The date and the
  /// notes are not compared.
  bool _isListed(
    Manifest existing,
    String version,
    int build,
    Map<String, FileEntry> files,
  ) {
    bool same(ReleaseEntry e) {
      if (e.version != version || e.build != build) return false;
      if (e.files.length != files.length) return false;
      for (final f in files.entries) {
        final listed = e.files[f.key];
        if (listed == null ||
            listed.url != f.value.url ||
            listed.size != f.value.size ||
            listed.sha256 != f.value.sha256) {
          return false;
        }
      }
      return true;
    }

    return [?existing.latest, ...existing.previous].any(same);
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
