/// Reads, changes and writes the two download lists that sit in the public
/// bucket: `releases/manifest.json` (desktop releases that are independent of
/// the stores) and `nightly/manifest.json`. Pure Dart, `dart:` libraries only,
/// so the publish command can run it with `dart tool/publish/publish.dart`
/// from any directory.
///
/// The file format is defined in
/// `docs/superpowers/specs/2026-10-07-website-design.md` (format 1):
///
/// ```json
/// {
///   "format": 1,
///   "latest": { "version": "1.2.0", "build": 45, "date": "2026-11-03",
///               "notes": "...", "files": { "windows-x64": { "url": "...",
///               "size": 1, "sha256": "..." } } },
///   "previous": [ { ...same entry shape... } ]
/// }
/// ```
///
/// Everything here is immutable: an operation never changes the manifest it
/// is given, it returns a new one.
library;

import 'dart:convert';

/// A publish step was refused, or a manifest could not be read. The message is
/// meant to be shown to the person running the command.
class PublishError implements Exception {
  const PublishError(this.message);

  final String message;

  @override
  String toString() => 'PublishError: $message';
}

/// Which list an artifact belongs to.
enum Lane { releases, nightly }

/// The version of the list format this library reads and writes.
const int manifestFormat = 1;

/// One downloadable file of a release. The platform it is for is the key in
/// [ReleaseEntry.files].
class FileEntry {
  const FileEntry({
    required this.url,
    required this.size,
    required this.sha256,
  });

  final String url;
  final int size;
  final String sha256;

  Map<String, Object?> _toJson() => {
    'url': url,
    'size': size,
    'sha256': sha256,
  };
}

/// One published version: a release or a single nightly.
class ReleaseEntry {
  /// [files] is copied; later changes to the map passed in do not show up
  /// here. Throws [PublishError] when [date] is not a real `YYYY-MM-DD` date.
  ReleaseEntry({
    required this.version,
    required this.build,
    required this.date,
    required this.notes,
    required Map<String, FileEntry> files,
  }) : files = Map.unmodifiable(files) {
    _requireDate(date, 'date');
  }

  final String version;
  final int build;

  /// Calendar date (UTC) the entry was published, `YYYY-MM-DD`.
  final String date;

  /// Markdown release notes; empty when there are none.
  final String notes;

  /// Download per platform key (`windows-x64`, `linux-x64`, `macos`, ...).
  /// Keys this library does not know about are kept as they are.
  final Map<String, FileEntry> files;

  Map<String, Object?> _toJson() => {
    'version': version,
    'build': build,
    'date': date,
    'notes': notes,
    'files': {for (final e in files.entries) e.key: e.value._toJson()},
  };
}

/// A download list: the newest entry and the ones before it, newest first.
class Manifest {
  /// [previous] is copied; later changes to the list passed in do not show up
  /// here.
  Manifest({this.latest, List<ReleaseEntry> previous = const []})
    : previous = List.unmodifiable(previous);

  /// A list with nothing published yet.
  static Manifest empty() => Manifest();

  /// The newest entry, or null while nothing is published.
  final ReleaseEntry? latest;

  /// Earlier entries, newest first.
  final List<ReleaseEntry> previous;

  /// Reads a list as written by [encode]. Throws [PublishError] for malformed
  /// JSON, a `format` other than 1, or a missing or wrongly typed field.
  /// `latest` and `previous` may be absent; `notes` may be absent in an entry.
  static Manifest parse(String json) {
    final Object? root;
    try {
      root = jsonDecode(json);
    } on FormatException catch (e) {
      throw PublishError('manifest is not valid JSON: ${e.message}');
    }
    final doc = _asObject(root, 'manifest');

    final format = doc['format'];
    if (format is! int || format != manifestFormat) {
      throw PublishError(
        'unsupported manifest format: ${format ?? 'missing'} '
        '(expected $manifestFormat)',
      );
    }

    final latestRaw = doc['latest'];
    final ReleaseEntry? latest = latestRaw == null
        ? null
        : _parseEntry(latestRaw, 'latest');

    final previousRaw = doc['previous'];
    final previous = <ReleaseEntry>[];
    if (previousRaw != null) {
      if (previousRaw is! List) {
        throw const PublishError('previous is not a list');
      }
      for (var i = 0; i < previousRaw.length; i++) {
        previous.add(_parseEntry(previousRaw[i], 'previous[$i]'));
      }
    }
    return Manifest(latest: latest, previous: previous);
  }

  /// Pretty JSON, 2-space indent, trailing newline, with a fixed key order so
  /// that publishing the same list twice writes the same bytes.
  String encode() {
    final doc = <String, Object?>{
      'format': manifestFormat,
      'latest': latest?._toJson(),
      'previous': [for (final e in previous) e._toJson()],
    };
    return '${const JsonEncoder.withIndent('  ').convert(doc)}\n';
  }
}

/// Publishes [e] as the new latest release; the old latest moves to the front
/// of `previous`. A version that is already in the list is refused, unless
/// [force] is set: then that entry is replaced where it is (the latest stays
/// the latest, a previous entry keeps its position).
Manifest addRelease(Manifest m, ReleaseEntry e, {bool force = false}) {
  PublishError already() => PublishError(
    'version ${e.version} is already published (use force to replace it)',
  );

  final latest = m.latest;
  if (latest != null && latest.version == e.version) {
    if (!force) throw already();
    return Manifest(latest: e, previous: m.previous);
  }

  final i = m.previous.indexWhere((p) => p.version == e.version);
  if (i >= 0) {
    if (!force) throw already();
    return Manifest(latest: latest, previous: [...m.previous]..[i] = e);
  }

  return Manifest(latest: e, previous: [?latest, ...m.previous]);
}

/// Publishes [e] as the new latest nightly; the old latest moves to the front
/// of `previous`. Nightlies are unique by build number. Afterwards every
/// previous entry dated before [now] (as a UTC calendar date) minus [keep] is
/// dropped; the new entry itself is never dropped.
Manifest addNightly(
  Manifest m,
  ReleaseEntry e, {
  required DateTime now,
  Duration keep = const Duration(days: 14),
}) {
  final latest = m.latest;
  final existing = [?latest, ...m.previous];
  if (existing.any((x) => x.build == e.build)) {
    throw PublishError('nightly build ${e.build} is already published');
  }

  final cutoff = _dateOnly(now.toUtc().subtract(keep));
  final previous = [
    for (final p in existing)
      if (!_parseDate(p.date)!.isBefore(cutoff)) p,
  ];
  return Manifest(latest: e, previous: previous);
}

/// Makes the earlier release [toVersion] the latest again. The old latest
/// goes to the front of `previous`; no entry is lost or duplicated. The
/// version has to be in `previous`.
Manifest rollback(Manifest m, String toVersion) {
  final latest = m.latest;
  if (latest != null && latest.version == toVersion) {
    throw PublishError('$toVersion is already the latest release');
  }
  final i = m.previous.indexWhere((p) => p.version == toVersion);
  if (i < 0) {
    throw PublishError('version $toVersion is not in the list of releases');
  }
  return Manifest(
    latest: m.previous[i],
    previous: [?latest, ...m.previous.take(i), ...m.previous.skip(i + 1)],
  );
}

/// The object key (path in the bucket) of one installer.
///
/// * release: `releases/<V>/Anchorline-<V>-<platform>.<ext>`
/// * nightly: `nightly/<V>-<N>/Anchorline-Nightly-<V>-<N>-<platform>.<ext>`
///
/// where `<N>` is [build]. A release key does not depend on [build].
String objectKey({
  required Lane lane,
  required String version,
  required int build,
  required String platformKey,
  required String extension,
}) => switch (lane) {
  Lane.releases =>
    'releases/$version/Anchorline-$version-$platformKey.$extension',
  Lane.nightly =>
    'nightly/$version-$build/'
        'Anchorline-Nightly-$version-$build-$platformKey.$extension',
};

// --- parsing helpers --------------------------------------------------------

ReleaseEntry _parseEntry(Object? raw, String where) {
  final map = _asObject(raw, where);
  final date = _string(map, 'date', where);
  _requireDate(date, '$where.date');
  return ReleaseEntry(
    version: _string(map, 'version', where),
    build: _int(map, 'build', where),
    date: date,
    notes: map['notes'] == null ? '' : _string(map, 'notes', where),
    files: _parseFiles(map['files'], '$where.files'),
  );
}

Map<String, FileEntry> _parseFiles(Object? raw, String where) {
  final map = _asObject(raw, where);
  return {
    for (final e in map.entries) e.key: _parseFile(e.value, '$where.${e.key}'),
  };
}

FileEntry _parseFile(Object? raw, String where) {
  final map = _asObject(raw, where);
  return FileEntry(
    url: _string(map, 'url', where),
    size: _int(map, 'size', where),
    sha256: _string(map, 'sha256', where),
  );
}

Map<String, Object?> _asObject(Object? value, String where) {
  if (value is Map) return value.cast<String, Object?>();
  throw PublishError('$where is missing or not an object');
}

String _string(Map<String, Object?> map, String key, String where) {
  final value = map[key];
  if (value is String) return value;
  throw PublishError('$where.$key is missing or not a string');
}

int _int(Map<String, Object?> map, String key, String where) {
  final value = map[key];
  if (value is int) return value;
  throw PublishError('$where.$key is missing or not an integer');
}

// --- dates ------------------------------------------------------------------

final RegExp _datePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Parses `YYYY-MM-DD` as midnight UTC; null for anything else, including
/// dates that do not exist (2026-02-31).
DateTime? _parseDate(String text) {
  final m = _datePattern.firstMatch(text);
  if (m == null) return null;
  final year = int.parse(m.group(1)!);
  final month = int.parse(m.group(2)!);
  final day = int.parse(m.group(3)!);
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

void _requireDate(String text, String where) {
  if (_parseDate(text) == null) {
    throw PublishError("$where must be a date like 2026-11-03, got '$text'");
  }
}

/// The calendar date of an instant that is already in UTC, as midnight UTC.
DateTime _dateOnly(DateTime utc) => DateTime.utc(utc.year, utc.month, utc.day);
